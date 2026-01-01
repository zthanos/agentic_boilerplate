defmodule AgentCore.WorkflowEngine.HistoryWorkflow.ComposeContextStep do
  @moduledoc """
  Step to compose historical context from selected candidates.

  This step takes the top-ranked candidate messages and formats them into
  a coherent context string that can be used for message augmentation.
  It handles formatting, ordering, and metadata inclusion.

  ## Input

  Expects either:
  - `ctx.artifacts[:history_top]` - Reranked candidates (if reranking was performed)
  - `ctx.artifacts[:history_candidates]` - Original candidates (if reranking was skipped)

  ## Output

  Sets `ctx.artifacts[:history_context]` with the formatted context string,
  and `ctx.artifacts[:history_items_used]` with the count of items included.

  ## Context Formatting

  The context is formatted as:
  - Clear section header
  - Chronologically ordered messages (oldest first for narrative flow)
  - Each message includes timestamp and content
  - Proper spacing and formatting for readability
  """

  @behaviour AgentCore.WorkflowEngine.Step

  @impl true
  def id, do: :compose_context

  @impl true
  def run(ctx, _input, opts) do
    # Try to get reranked candidates first, fall back to original candidates
    candidates =
      AgentCore.WorkflowEngine.Context.get_artifact(ctx, :history_top) ||
        AgentCore.WorkflowEngine.Context.get_artifact(ctx, :history_candidates)

    if is_nil(candidates) or candidates == [] do
      # No candidates available - set nil context
      updated_ctx =
        ctx
        |> AgentCore.WorkflowEngine.Context.put_artifact(:history_context, nil)
        |> AgentCore.WorkflowEngine.Context.put_artifact(:history_items_used, 0)

      output = %{
        context_created: false,
        items_used: 0,
        reason: "No candidates available"
      }

      {:ok, updated_ctx, output}
    else
      # Compose context from candidates
      {context_string, items_used} = compose_context_string(candidates, opts)

      updated_ctx =
        ctx
        |> AgentCore.WorkflowEngine.Context.put_artifact(:history_context, context_string)
        |> AgentCore.WorkflowEngine.Context.put_artifact(:history_items_used, items_used)

      output = %{
        context_created: true,
        items_used: items_used,
        context_length: String.length(context_string || "")
      }

      {:ok, updated_ctx, output}
    end
  end

  # Private function to compose the context string
  defp compose_context_string(candidates, opts) do
    # Configuration
    max_items = Map.get(opts, :max_items, 5)
    max_length = Map.get(opts, :max_context_length, 2000)
    include_timestamps = Map.get(opts, :include_timestamps, true)

    # Take up to max_items candidates
    selected_candidates = Enum.take(candidates, max_items)

    if selected_candidates == [] do
      {nil, 0}
    else
      # Sort by timestamp (oldest first for chronological narrative)
      sorted_candidates =
        Enum.sort_by(
          selected_candidates,
          fn candidate ->
            candidate.metadata[:timestamp] || DateTime.utc_now()
          end,
          DateTime
        )

      # Format each candidate
      formatted_items =
        Enum.map(sorted_candidates, fn candidate ->
          format_candidate(candidate, include_timestamps)
        end)

      # Compose the full context
      context_header = "## Relevant Previous Context\n\n"
      context_body = Enum.join(formatted_items, "\n\n")
      full_context = context_header <> context_body

      # Truncate if too long
      final_context =
        if String.length(full_context) > max_length do
          truncated = String.slice(full_context, 0, max_length - 3)
          truncated <> "..."
        else
          full_context
        end

      {final_context, length(selected_candidates)}
    end
  end

  # Format a single candidate for inclusion in context
  defp format_candidate(candidate, include_timestamps) do
    content = candidate.content || ""

    if include_timestamps and candidate.metadata[:timestamp] do
      timestamp = candidate.metadata[:timestamp]
      formatted_time = format_timestamp(timestamp)
      "**#{formatted_time}:** #{content}"
    else
      "- #{content}"
    end
  end

  # Format timestamp for display
  defp format_timestamp(timestamp) do
    case DateTime.from_iso8601(to_string(timestamp)) do
      {:ok, dt, _} ->
        Calendar.strftime(dt, "%Y-%m-%d %H:%M")

      _ ->
        # Fallback if timestamp parsing fails
        case timestamp do
          %DateTime{} = dt ->
            Calendar.strftime(dt, "%Y-%m-%d %H:%M")

          _ ->
            "Recent"
        end
    end
  rescue
    _ ->
      "Recent"
  end
end
