defmodule AgentCore.WorkflowEngine.HistoryWorkflow.RerankCandidatesStep do
  @moduledoc """
  Step to rerank candidate messages for improved relevance.

  This step takes the candidates retrieved from vector search and applies
  additional ranking logic to improve relevance. It can use various signals
  like recency, content quality, and contextual relevance.

  ## Input

  Expects `ctx.artifacts[:history_candidates]` containing a list of candidates
  with content, score, and metadata.

  ## Output

  Sets `ctx.artifacts[:history_top]` with the top-ranked candidates after
  reranking, maintaining the same structure but with updated scores.

  ## Reranking Logic

  The reranking considers:
  - Original similarity score
  - Recency of the message (newer messages get slight boost)
  - Content quality indicators
  - Diversity to avoid redundant results
  """

  @behaviour AgentCore.WorkflowEngine.Step

  @impl true
  def id, do: :rerank_candidates

  @impl true
  def run(ctx, _input, opts) do
    # Get candidates from context
    candidates = AgentCore.WorkflowEngine.Context.get_artifact(ctx, :history_candidates)

    if is_nil(candidates) or candidates == [] do
      # If no candidates, skip reranking
      {:skip, ctx, %{reason: "No candidates to rerank", candidates_count: 0}}
    else
      # Perform reranking
      top_candidates = rerank_candidates(candidates, opts)

      updated_ctx =
        AgentCore.WorkflowEngine.Context.put_artifact(ctx, :history_top, top_candidates)

      output = %{
        original_count: length(candidates),
        reranked_count: length(top_candidates),
        top_score: if(length(top_candidates) > 0, do: hd(top_candidates).score, else: 0.0)
      }

      {:ok, updated_ctx, output}
    end
  end

  # Private function to rerank candidates
  defp rerank_candidates(candidates, opts) do
    # Configuration
    max_results = Map.get(opts, :max_results, 5)
    recency_weight = Map.get(opts, :recency_weight, 0.1)
    diversity_threshold = Map.get(opts, :diversity_threshold, 0.8)

    # Apply reranking algorithm
    candidates
    |> apply_recency_boost(recency_weight)
    |> apply_quality_scoring()
    |> ensure_diversity(diversity_threshold)
    |> Enum.sort_by(& &1.score, :desc)
    |> Enum.take(max_results)
  end

  # Apply recency boost to scores
  defp apply_recency_boost(candidates, recency_weight) do
    now = DateTime.utc_now()

    Enum.map(candidates, fn candidate ->
      # Calculate hours since the message
      timestamp = candidate.metadata[:timestamp] || now
      hours_ago = DateTime.diff(now, timestamp, :hour)

      # Apply exponential decay for recency (newer = higher boost)
      # Max boost of recency_weight for messages < 1 hour old
      recency_boost = recency_weight * :math.exp(-hours_ago / 24.0)

      # Update score
      new_score = candidate.score + recency_boost
      %{candidate | score: new_score}
    end)
  end

  # Apply content quality scoring
  defp apply_quality_scoring(candidates) do
    Enum.map(candidates, fn candidate ->
      content = candidate.content || ""

      # Simple quality indicators
      quality_score = calculate_quality_score(content)

      # Small boost for higher quality content (max 0.05)
      quality_boost = quality_score * 0.05

      new_score = candidate.score + quality_boost
      %{candidate | score: new_score}
    end)
  end

  # Calculate a simple quality score for content
  defp calculate_quality_score(content) do
    # Normalize content length (prefer substantial but not too long content)
    length = String.length(content)

    length_score =
      cond do
        # Too short
        length < 20 -> 0.3
        # Too long
        length > 500 -> 0.7
        # Good length
        true -> 1.0
      end

    # Check for complete sentences (ends with punctuation)
    punctuation_score =
      if String.match?(content, ~r/[.!?]$/) do
        1.0
      else
        0.8
      end

    # Combine scores
    (length_score + punctuation_score) / 2.0
  end

  # Ensure diversity in results by removing very similar candidates
  defp ensure_diversity(candidates, similarity_threshold) do
    # Simple diversity check - remove candidates that are too similar to higher-scored ones
    {selected, _} =
      Enum.reduce(candidates, {[], []}, fn candidate, {selected, seen_content} ->
        content = String.downcase(candidate.content || "")

        # Check if this content is too similar to any already selected
        is_too_similar =
          Enum.any?(seen_content, fn seen ->
            content_similarity(content, seen) > similarity_threshold
          end)

        if is_too_similar do
          # Skip this candidate
          {selected, seen_content}
        else
          # Include this candidate
          {[candidate | selected], [content | seen_content]}
        end
      end)

    Enum.reverse(selected)
  end

  # Simple content similarity check (Jaccard similarity on words)
  defp content_similarity(content1, content2) do
    words1 = content1 |> String.split() |> MapSet.new()
    words2 = content2 |> String.split() |> MapSet.new()

    intersection_size = MapSet.intersection(words1, words2) |> MapSet.size()
    union_size = MapSet.union(words1, words2) |> MapSet.size()

    if union_size == 0 do
      0.0
    else
      intersection_size / union_size
    end
  end
end
