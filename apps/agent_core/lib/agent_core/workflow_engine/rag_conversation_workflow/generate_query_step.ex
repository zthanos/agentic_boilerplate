defmodule AgentCore.WorkflowEngine.RagConversationWorkflow.GenerateQueryStep do
  @moduledoc """
  Step to generate structured queries for vector database search using LLM analysis.

  This step analyzes user messages and generates optimized queries for retrieving
  relevant historical context from conversation history. It uses LLM to understand
  the semantic intent and create structured search parameters.

  ## Input

  Expects input containing:
  - `user_message` - The user message to analyze
  - `conversation_id` - Optional conversation identifier
  - `user_context` - Additional context about the user/conversation
  - `profile` - LLM profile for query generation
  - `overrides` - LLM overrides for execution

  ## Output

  Sets `ctx.artifacts[:history_query]` with the generated query or sets
  `ctx.decisions[:skip_history]` to true if no query is needed.

  ## Query Generation Logic

  Uses LLM to analyze the message and generate structured queries optimized
  for vector database retrieval. Falls back to skipping history if LLM fails.
  """

  @behaviour AgentCore.WorkflowEngine.Step

  require Logger
  alias AgentCore.Providers.Response

  @impl true
  def id, do: :generate_query

  @impl true
  def run(ctx, input, opts) do
    Logger.info("[GenerateQueryStep] Starting execution")
    Logger.debug("[GenerateQueryStep] Input keys: #{inspect(Map.keys(input))}")
    Logger.debug("[GenerateQueryStep] Context: #{inspect(ctx)}")
    Logger.debug("[GenerateQueryStep] Opts: #{inspect(opts)}")

    user_message = Map.get(input, :user_message, "")
    conversation_id = Map.get(input, :conversation_id)
    profile = Map.get(input, :profile)
    overrides = Map.get(input, :overrides, %{})

    Logger.info("[GenerateQueryStep] user_message: #{inspect(user_message)}")
    Logger.info("[GenerateQueryStep] conversation_id: #{inspect(conversation_id)}")
    Logger.info("[GenerateQueryStep] profile: #{inspect(profile)}")

    # Skip if no conversation_id (can't retrieve history anyway)
    if is_nil(conversation_id) do
      Logger.info("[GenerateQueryStep] Skipping - no conversation_id")
      updated_ctx = AgentCore.WorkflowEngine.Context.put_decision(ctx, :skip_history, true)

      output = %{
        skipped: true,
        reason: "no_conversation_id",
        message_length: String.length(user_message)
      }

      Logger.info("[GenerateQueryStep] Completed with skip - no conversation_id")
      {:ok, updated_ctx, output}
    else
      Logger.info("[GenerateQueryStep] Generating history query")

      case generate_history_query(user_message, profile, overrides, opts) do
        {:ok, query} ->
          Logger.info("[GenerateQueryStep] Query generated successfully: #{inspect(query)}")
          updated_ctx = AgentCore.WorkflowEngine.Context.put_artifact(ctx, :history_query, query)

          output = %{
            query_generated: true,
            query: query,
            message_length: String.length(user_message)
          }

          Logger.info("[GenerateQueryStep] Completed successfully")
          {:ok, updated_ctx, output}

        {:error, reason} ->
          Logger.warning("[GenerateQueryStep] Query generation failed: #{inspect(reason)}")

          updated_ctx = AgentCore.WorkflowEngine.Context.put_decision(ctx, :skip_history, true)

          output = %{
            skipped: true,
            reason: "llm_generation_failed",
            error: reason,
            message_length: String.length(user_message)
          }

          Logger.info("[GenerateQueryStep] Completed with skip - LLM generation failed")
          {:ok, updated_ctx, output}
      end
    end
  rescue
    exception ->
      Logger.error("[GenerateQueryStep] Exception occurred: #{Exception.message(exception)}")
      Logger.error("[GenerateQueryStep] Stacktrace: #{inspect(__STACKTRACE__)}")

      updated_ctx = AgentCore.WorkflowEngine.Context.put_decision(ctx, :skip_history, true)

      output = %{
        skipped: true,
        reason: "step_exception",
        error: Exception.message(exception),
        message_length: String.length(Map.get(input, :user_message, ""))
      }

      {:ok, updated_ctx, output}
  end

  # Generate structured query using LLM
  defp generate_history_query(message, profile, overrides, opts) when not is_nil(profile) do
    Logger.info("[GenerateQueryStep] Starting LLM query generation")
    Logger.debug("[GenerateQueryStep] Message: #{inspect(message)}")
    Logger.debug("[GenerateQueryStep] Profile: #{inspect(profile)}")
    Logger.debug("[GenerateQueryStep] Overrides: #{inspect(overrides)}")

    # Get system prompt from options or use default
    system_prompt = get_system_prompt(opts)
    Logger.debug("[GenerateQueryStep] System prompt length: #{String.length(system_prompt)}")

    # Build LLM input for query generation
    llm_input = %{
      type: :chat,
      messages: [
        %{role: :system, content: system_prompt},
        %{role: :user, content: message}
      ]
    }

    Logger.debug("[GenerateQueryStep] LLM input prepared")

    # Build execution metadata
    exec_meta = %{
      "phase" => "generate_history_query"
    }

    Logger.info("[GenerateQueryStep] Calling LLM executor")

    # Try to call the LLM executor, but handle the case where it's not available
    try do
      # Check if AgentRuntime.Llm.Executor is available
      if Code.ensure_loaded?(AgentRuntime.Llm.Executor) do
        Logger.info("[GenerateQueryStep] AgentRuntime.Llm.Executor is available, calling it")

        case AgentRuntime.Llm.Executor.execute(profile, overrides, llm_input, exec_meta) do
          {:ok, %{response: response}} ->
            Logger.info("[GenerateQueryStep] LLM execution successful")
            Logger.debug("[GenerateQueryStep] Response: #{inspect(response)}")

            # Extract and parse the response
            case Response.content(response) do
              text when is_binary(text) and text != "" ->
                Logger.info("[GenerateQueryStep] Parsing response text: #{inspect(text)}")
                parse_query_response(text)

              _ ->
                Logger.warning("[GenerateQueryStep] Empty or invalid response content")
                {:error, "invalid_response_format"}
            end

          {:error, reason} ->
            Logger.error("[GenerateQueryStep] LLM execution failed: #{inspect(reason)}")
            {:error, reason}
        end
      else
        Logger.error("[GenerateQueryStep] AgentRuntime.Llm.Executor module not available")
        {:error, "llm_executor_not_available"}
      end
    rescue
      exception ->
        Logger.error(
          "[GenerateQueryStep] Exception in generate_history_query: #{Exception.message(exception)}"
        )

        Logger.error("[GenerateQueryStep] Stacktrace: #{inspect(__STACKTRACE__)}")
        {:error, "llm_execution_exception: #{Exception.message(exception)}"}
    end
  end

  defp generate_history_query(_message, _profile, _overrides, _opts) do
    {:error, "no_profile"}
  end

  # Parse LLM response to extract structured query
  defp parse_query_response(text) do
    try do
      # Try to parse as JSON first
      case Jason.decode(text) do
        {:ok, %{"query" => query}} when is_binary(query) and query != "" ->
          {:ok, query}

        {:ok, parsed} ->
          # Try to extract query from various possible formats
          query = extract_query_from_parsed(parsed)

          if is_binary(query) and String.trim(query) != "" do
            {:ok, String.trim(query)}
          else
            {:error, "no_valid_query_in_response"}
          end

        {:error, _} ->
          # If not JSON, try to extract query from plain text
          extract_query_from_text(text)
      end
    rescue
      _ ->
        extract_query_from_text(text)
    end
  end

  # Extract query from parsed JSON response
  defp extract_query_from_parsed(parsed) when is_map(parsed) do
    # Try various possible keys
    Enum.find_value(["query", "search_query", "history_query", "search"], fn key ->
      case Map.get(parsed, key) do
        query when is_binary(query) and query != "" -> query
        _ -> nil
      end
    end)
  end

  defp extract_query_from_parsed(_), do: nil

  # Extract query from plain text response
  defp extract_query_from_text(text) do
    # Clean up the text
    cleaned = String.trim(text)

    # If it looks like a reasonable query (not too short, not too long)
    if String.length(cleaned) >= 3 and String.length(cleaned) <= 500 do
      {:ok, cleaned}
    else
      {:error, "invalid_query_length"}
    end
  end

  # Get system prompt for query generation
  defp get_system_prompt(opts) do
    Map.get(opts, :system_prompt, default_system_prompt())
  end

  # Default system prompt for query generation
  defp default_system_prompt do
    """
    You are an assistant that generates search queries for retrieving relevant conversation history.

    Given a user message, generate a concise search query that would help find relevant previous conversations or context.

    Guidelines:
    - Focus on the key concepts, topics, or entities mentioned
    - Use natural language that would match similar discussions
    - Keep queries concise but descriptive (3-50 words)
    - Avoid overly specific details that might miss relevant context
    - If the message is a greeting or doesn't need history, respond with an empty string

    Respond with ONLY the search query text, no additional formatting or explanation.

    Examples:
    User: "How did the deployment go yesterday?"
    Response: deployment status yesterday results

    User: "Can you continue working on the authentication feature?"
    Response: authentication feature development progress

    User: "Hello"
    Response:

    User: "What was the error we discussed about the database?"
    Response: database error discussion problem
    """
  end
end
