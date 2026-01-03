defmodule AgentCore.WorkflowEngine.HistoryWorkflow.AssessNeedStep do
  @moduledoc """
  Step to evaluate if history is needed for the current message.

  This step analyzes the current message to determine whether historical context
  would be beneficial for processing. It uses an LLM to make an intelligent
  routing decision that affects the workflow path.

  ## Input

  Expects input containing:
  - `current_message` - The message to analyze
  - `conversation_id` - Optional conversation identifier
  - `profile` - LLM profile for assessment
  - `overrides` - LLM overrides
  - `on_chunk` - Streaming callback (optional)

  ## Output

  Sets `ctx.decisions[:needs_history]` to `true` or `false` based on the analysis.

  ## Decision Logic

  Uses an LLM to analyze the message and determine if historical context would be helpful.
  Falls back to simple heuristics if LLM call fails.
  """

  @behaviour AgentCore.WorkflowEngine.Step

  @impl true
  def id, do: :assess_need

  @impl true
  def run(ctx, input, _opts) do
    current_message = Map.get(input, :current_message, "")
    conversation_id = Map.get(input, :conversation_id)
    profile = Map.get(input, :profile)
    overrides = Map.get(input, :overrides, %{})

    needs_history = assess_need_for_history(current_message, conversation_id, profile, overrides)

    updated_ctx =
      AgentCore.WorkflowEngine.Context.put_decision(ctx, :needs_history, needs_history)

    output = %{
      needs_history: needs_history,
      message_length: String.length(current_message),
      has_conversation_id: not is_nil(conversation_id)
    }

    {:ok, updated_ctx, output}
  end

  # Private function to determine if history is needed using LLM
  defp assess_need_for_history(message, conversation_id, profile, overrides) do
    # If no conversation_id, we can't retrieve history anyway
    if is_nil(conversation_id) do
      false
    else
      # Try LLM-based assessment first
      case llm_assess_need(message, profile, overrides) do
        {:ok, needs_history} -> needs_history
        {:error, _reason} -> fallback_assess_need(message)
      end
    end
  end

  # Use LLM to assess if history is needed
  defp llm_assess_need(message, profile, overrides) when not is_nil(profile) do
    # Build LLM input for assessment
    llm_input = %{
      type: :chat,
      messages: [
        %{
          role: :system,
          content: """
          You are an assistant that determines if a user message would benefit from historical context from previous conversations.

          Respond with exactly "YES" if the message:
          - References previous conversations or interactions
          - Asks about past events, decisions, or outcomes
          - Uses words like "before", "earlier", "last time", "remember", "continue", "follow up"
          - Would be better understood with context from prior messages

          Respond with exactly "NO" if the message:
          - Is a standalone question or statement
          - Is a greeting or simple query
          - Can be fully understood without additional context
          - Is asking for general information

          Only respond with "YES" or "NO", nothing else.
          """
        },
        %{
          role: :user,
          content: message
        }
      ]
    }

    # Build execution metadata
    exec_meta = %{
      "phase" => "assess_history_need"
    }

    # Execute LLM request
    case AgentRuntime.Llm.Executor.execute(profile, overrides, llm_input, exec_meta) do
      {:ok, %{response: response}} ->
        # Extract the response text
        response_text =
          case response.output_text do
            text when is_binary(text) -> String.trim(String.upcase(text))
            _ -> "NO"
          end

        needs_history = response_text == "YES"
        {:ok, needs_history}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp llm_assess_need(_message, _profile, _overrides) do
    {:error, "no_profile"}
  end

  # Fallback assessment using simple heuristics
  defp fallback_assess_need(message) do
    message_lower = String.downcase(message)

    # Keywords that suggest reference to previous context
    history_indicators = [
      "before",
      "earlier",
      "previously",
      "last time",
      "remember",
      "recall",
      "we discussed",
      "you said",
      "mentioned",
      "talked about",
      "continue",
      "follow up",
      "update",
      "progress",
      "status",
      "what happened",
      "how did",
      "result",
      "outcome"
    ]

    # Check if message contains any history indicators
    has_history_indicators =
      Enum.any?(history_indicators, fn indicator ->
        String.contains?(message_lower, indicator)
      end)

    # Also consider message length - very short messages might not need history
    message_length = String.length(String.trim(message))
    is_substantial_message = message_length > 10

    # Need history if we have indicators and it's a substantial message
    has_history_indicators and is_substantial_message
  end
end
