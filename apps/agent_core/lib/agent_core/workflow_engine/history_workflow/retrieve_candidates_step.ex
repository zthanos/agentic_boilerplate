defmodule AgentCore.WorkflowEngine.HistoryWorkflow.RetrieveCandidatesStep do
  @moduledoc """
  Step to retrieve candidate messages from conversation history.

  This step performs vector similarity search against conversation history using
  the query built in the previous step. It integrates with the vector search
  system to find relevant historical messages.

  ## Input

  Expects `ctx.artifacts[:history_query]` containing:
  - `query` - The search query string
  - `filters` - Search filters (e.g., conversation_id)
  - `k` - Number of candidates to retrieve

  ## Output

  Sets `ctx.artifacts[:history_candidates]` with a list of candidate messages,
  each containing:
  - `content` - The message content
  - `score` - Similarity score
  - `metadata` - Additional metadata (timestamp, user, etc.)

  ## Integration

  This step would typically integrate with a vector database or search service.
  For now, it provides a mock implementation that can be replaced with actual
  vector search integration.
  """

  @behaviour AgentCore.WorkflowEngine.Step

  @impl true
  def id, do: :retrieve_candidates

  @impl true
  def run(ctx, _input, opts) do
    # Get the history query from context
    history_query = AgentCore.WorkflowEngine.Context.get_artifact(ctx, :history_query)

    if is_nil(history_query) do
      {:error, ctx, %{error: "No history query found in context", step: :retrieve_candidates}}
    else
      # Perform the search
      candidates = perform_vector_search(history_query, opts)

      updated_ctx =
        AgentCore.WorkflowEngine.Context.put_artifact(ctx, :history_candidates, candidates)

      output = %{
        candidates_found: length(candidates),
        query_used: history_query.query,
        search_filters: history_query.filters
      }

      {:ok, updated_ctx, output}
    end
  end

  # Private function to perform vector search
  # This is a mock implementation that would be replaced with actual vector search
  defp perform_vector_search(history_query, opts) do
    # Extract search parameters
    query = history_query.query
    filters = history_query.filters
    k = history_query.k

    # Mock implementation - in a real system this would:
    # 1. Convert the query to a vector embedding
    # 2. Search the vector database with the embedding
    # 3. Apply filters (conversation_id, etc.)
    # 4. Return top-k results with similarity scores

    # For now, return mock candidates based on the query
    mock_candidates = generate_mock_candidates(query, filters, k, opts)

    # Sort by score (highest first) and limit to k results
    mock_candidates
    |> Enum.sort_by(& &1.score, :desc)
    |> Enum.take(k)
  end

  # Generate mock candidates for testing purposes
  defp generate_mock_candidates(query, filters, k, opts) do
    # Check if we should return empty results (for testing empty case)
    return_empty = Map.get(opts, :return_empty, false)

    if return_empty do
      []
    else
      # Generate some mock candidates
      base_candidates = [
        %{
          content:
            "I remember we discussed #{query} in our previous conversation. The key points were...",
          score: 0.85,
          metadata: %{
            timestamp: DateTime.utc_now() |> DateTime.add(-3600, :second),
            message_id: "msg_001",
            conversation_id: filters[:conversation_id] || "conv_001"
          }
        },
        %{
          content: "Following up on #{query}, here are the results from last time...",
          score: 0.72,
          metadata: %{
            timestamp: DateTime.utc_now() |> DateTime.add(-7200, :second),
            message_id: "msg_002",
            conversation_id: filters[:conversation_id] || "conv_001"
          }
        },
        %{
          content: "The #{query} topic came up before, and we found that...",
          score: 0.68,
          metadata: %{
            timestamp: DateTime.utc_now() |> DateTime.add(-10800, :second),
            message_id: "msg_003",
            conversation_id: filters[:conversation_id] || "conv_001"
          }
        }
      ]

      # Return up to k candidates
      Enum.take(base_candidates, min(k, length(base_candidates)))
    end
  end
end
