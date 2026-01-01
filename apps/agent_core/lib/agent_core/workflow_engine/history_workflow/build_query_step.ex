defmodule AgentCore.WorkflowEngine.HistoryWorkflow.BuildQueryStep do
  @moduledoc """
  Step to build a query for retrieving historical context.

  This step generates a structured query from the current message that can be used
  for vector similarity search against conversation history.

  ## Input

  Expects input containing:
  - `current_message` - The message to generate a query from
  - `conversation_id` - Conversation identifier for filtering

  ## Output

  Sets `ctx.artifacts[:history_query]` with:
  - `query` - The search query string
  - `filters` - Additional filters for the search
  - `k` - Number of candidates to retrieve

  ## Query Generation Logic

  The query is built by:
  - Extracting key terms and concepts from the current message
  - Removing common stop words
  - Focusing on nouns, verbs, and important adjectives
  - Including context about the type of information needed
  """

  @behaviour AgentCore.WorkflowEngine.Step

  @impl true
  def id, do: :build_query

  @impl true
  def run(ctx, input, opts) do
    current_message = Map.get(input, :current_message, "")
    conversation_id = Map.get(input, :conversation_id)

    # Extract configuration from opts
    max_candidates = Map.get(opts, :max_candidates, 10)

    query = build_search_query(current_message)
    filters = build_search_filters(conversation_id)

    history_query = %{
      query: query,
      filters: filters,
      k: max_candidates
    }

    updated_ctx =
      AgentCore.WorkflowEngine.Context.put_artifact(ctx, :history_query, history_query)

    output = %{
      query_length: String.length(query),
      filter_count: map_size(filters),
      max_candidates: max_candidates
    }

    {:ok, updated_ctx, output}
  end

  # Private function to build the search query from the message
  defp build_search_query(message) do
    # Clean and normalize the message
    cleaned_message =
      message
      |> String.trim()
      |> String.downcase()

    # Extract meaningful terms (simple approach - remove common stop words)
    stop_words =
      MapSet.new([
        "the",
        "a",
        "an",
        "and",
        "or",
        "but",
        "in",
        "on",
        "at",
        "to",
        "for",
        "of",
        "with",
        "by",
        "is",
        "are",
        "was",
        "were",
        "be",
        "been",
        "have",
        "has",
        "had",
        "do",
        "does",
        "did",
        "will",
        "would",
        "could",
        "should",
        "may",
        "might",
        "can",
        "this",
        "that",
        "these",
        "those",
        "i",
        "you",
        "he",
        "she",
        "it",
        "we",
        "they",
        "me",
        "him",
        "her",
        "us",
        "them"
      ])

    # Split into words and filter out stop words
    meaningful_words =
      cleaned_message
      |> String.split(~r/\W+/, trim: true)
      # Remove very short words
      |> Enum.reject(&(String.length(&1) < 3))
      |> Enum.reject(&MapSet.member?(stop_words, &1))
      # Limit to top 10 terms to keep query focused
      |> Enum.take(10)

    # If we have meaningful words, use them; otherwise use the original message
    if length(meaningful_words) > 0 do
      Enum.join(meaningful_words, " ")
    else
      # Fallback to the original message if no meaningful words found
      # Limit length
      String.slice(cleaned_message, 0, 100)
    end
  end

  # Private function to build search filters
  defp build_search_filters(conversation_id) do
    filters = %{}

    # Add conversation filter if available
    if conversation_id do
      Map.put(filters, :conversation_id, conversation_id)
    else
      filters
    end
  end
end
