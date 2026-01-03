defmodule AgentCore.WorkflowEngine.RagConversationWorkflow.EnhancePromptStep do
  @moduledoc """
  Step to enhance user prompts with retrieved historical context.

  This step takes the original user message and augments it with relevant
  historical context retrieved from the vector database. It formats the
  context in a structured way that preserves conversation flow and provides
  the LLM with relevant background information.

  ## Input

  Expects:
  - `user_message` from workflow input - The original user message
  - `ctx.artifacts[:retrieved_context]` - List of relevant context items from previous step

  ## Output

  Sets `ctx.artifacts[:enhanced_prompt]` with the augmented prompt that includes
  both the original message and formatted historical context.

  ## Context Formatting

  The step formats historical context in a structured way that:
  - Preserves conversation flow and readability
  - Provides clear separation between historical context and current message
  - Includes metadata about the context items used
  - Maintains workflow-specific formatting without dependencies on plan system utilities

  ## Error Handling

  Handles cases where no context is available gracefully by returning the
  original prompt unchanged. Provides detailed output for observability.
  """

  @behaviour AgentCore.WorkflowEngine.Step

  require Logger

  @impl true
  def id, do: :enhance_prompt

  @impl true
  def run(ctx, input, opts) do
    user_message = Map.get(input, :user_message, "")

    retrieved_context =
      AgentCore.WorkflowEngine.Context.get_artifact(ctx, :retrieved_context) || []

    case enhance_prompt_with_context(user_message, retrieved_context, opts) do
      {:ok, enhanced_prompt, context_info} ->
        updated_ctx =
          AgentCore.WorkflowEngine.Context.put_artifact(ctx, :enhanced_prompt, enhanced_prompt)

        output = %{
          enhanced: true,
          original_length: String.length(user_message),
          enhanced_length: String.length(enhanced_prompt),
          context_items_used: Map.get(context_info, :context_items, 0),
          context_info: context_info
        }

        {:ok, updated_ctx, output}

      {:error, reason} ->
        Logger.warning("[workflow] enhance_prompt failed: #{inspect(reason)}")

        # Fall back to original message on error
        updated_ctx =
          AgentCore.WorkflowEngine.Context.put_artifact(ctx, :enhanced_prompt, user_message)

        output = %{
          enhanced: false,
          fallback_used: true,
          error: reason,
          original_length: String.length(user_message),
          enhanced_length: String.length(user_message)
        }

        {:ok, updated_ctx, output}
    end
  end

  # Enhance the prompt with retrieved historical context
  defp enhance_prompt_with_context(user_message, [], _opts) do
    # No context available, return original message
    {:ok, user_message, %{context_items: 0, context_summary: "no_context_available"}}
  end

  defp enhance_prompt_with_context(user_message, context_items, opts)
       when is_list(context_items) do
    try do
      # Filter and prepare context items
      prepared_context = prepare_context_items(context_items, opts)

      if Enum.empty?(prepared_context) do
        {:ok, user_message, %{context_items: 0, context_summary: "no_relevant_context"}}
      else
        # Format the enhanced prompt
        enhanced_prompt = format_enhanced_prompt(user_message, prepared_context, opts)

        context_info = %{
          context_items: length(prepared_context),
          context_summary: summarize_context_usage(prepared_context),
          top_score: get_top_context_score(prepared_context),
          avg_score: get_average_context_score(prepared_context)
        }

        {:ok, enhanced_prompt, context_info}
      end
    rescue
      error ->
        {:error, {:formatting_error, error}}
    end
  end

  defp enhance_prompt_with_context(_user_message, _context_items, _opts) do
    {:error, :invalid_context_format}
  end

  # Prepare context items for inclusion in the prompt
  defp prepare_context_items(context_items, opts) do
    # Get configuration from options
    max_items = Map.get(opts, :max_context_items, 5)
    min_score = Map.get(opts, :min_context_score, 0.3)
    max_content_length = Map.get(opts, :max_content_length, 500)

    context_items
    |> Enum.filter(fn item ->
      # Filter by minimum score
      score = Map.get(item, :score, 0.0)
      score >= min_score
    end)
    |> Enum.take(max_items)
    |> Enum.map(fn item ->
      # Truncate content if too long
      content = Map.get(item, :content, "")
      truncated_content = truncate_content(content, max_content_length)

      %{
        content: truncated_content,
        score: Map.get(item, :score, 0.0),
        metadata: Map.get(item, :metadata, %{})
      }
    end)
  end

  # Format the enhanced prompt with historical context
  defp format_enhanced_prompt(user_message, context_items, opts) do
    # Get formatting options
    include_scores = Map.get(opts, :include_context_scores, false)
    context_header = Map.get(opts, :context_header, "Relevant conversation history:")
    separator = Map.get(opts, :context_separator, "\n---\n")

    # Build context section
    context_section = build_context_section(context_items, include_scores, context_header)

    # Combine original message with context
    if String.trim(context_section) == "" do
      user_message
    else
      """
      #{context_section}#{separator}Current message: #{user_message}
      """
    end
  end

  # Build the context section of the enhanced prompt
  defp build_context_section(context_items, include_scores, header) do
    if Enum.empty?(context_items) do
      ""
    else
      context_entries =
        Enum.map_join(context_items, "\n\n", fn item ->
          format_context_item(item, include_scores)
        end)

      """
      #{header}

      #{context_entries}
      """
    end
  end

  # Format a single context item for inclusion in the prompt
  defp format_context_item(item, include_scores) do
    content = Map.get(item, :content, "")
    score = Map.get(item, :score, 0.0)
    metadata = Map.get(item, :metadata, %{})

    # Format timestamp if available
    timestamp_info = format_timestamp_info(metadata)

    if include_scores do
      score_text = :erlang.float_to_binary(score, decimals: 2)
      "#{content}#{timestamp_info} (relevance: #{score_text})"
    else
      "#{content}#{timestamp_info}"
    end
  end

  # Format timestamp information from metadata
  defp format_timestamp_info(metadata) when is_map(metadata) do
    case Map.get(metadata, :timestamp) do
      %DateTime{} = dt ->
        formatted_time = DateTime.to_string(dt)
        " [#{formatted_time}]"

      timestamp when is_binary(timestamp) ->
        " [#{timestamp}]"

      _ ->
        ""
    end
  end

  defp format_timestamp_info(_), do: ""

  # Truncate content to maximum length with ellipsis
  defp truncate_content(content, max_length) when is_binary(content) do
    if String.length(content) <= max_length do
      content
    else
      truncated = String.slice(content, 0, max_length - 3)
      "#{truncated}..."
    end
  end

  defp truncate_content(content, _max_length), do: to_string(content)

  # Summarize context usage for output
  defp summarize_context_usage(context_items) do
    count = length(context_items)

    if count == 0 do
      "no_context"
    else
      avg_score = get_average_context_score(context_items)
      score_text = :erlang.float_to_binary(avg_score, decimals: 2)
      "#{count}_items_avg_score_#{score_text}"
    end
  end

  # Get the highest context score
  defp get_top_context_score([]), do: nil

  defp get_top_context_score(context_items) do
    context_items
    |> Enum.map(fn item -> Map.get(item, :score, 0.0) end)
    |> Enum.max()
  end

  # Get the average context score
  defp get_average_context_score([]), do: 0.0

  defp get_average_context_score(context_items) do
    scores = Enum.map(context_items, fn item -> Map.get(item, :score, 0.0) end)
    Enum.sum(scores) / length(scores)
  end
end
