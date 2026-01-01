defmodule AgentCore.WorkflowEngine.HistoryWorkflow.AssessNeedStep do
  @moduledoc """
  Step to evaluate if history is needed for the current message.

  This step analyzes the current message to determine whether historical context
  would be beneficial for processing. It makes a routing decision that affects
  the workflow path.

  ## Input

  Expects input containing:
  - `current_message` - The message to analyze
  - `conversation_id` - Optional conversation identifier

  ## Output

  Sets `ctx.decisions[:needs_history]` to `true` or `false` based on the analysis.

  ## Decision Logic

  History is considered needed when:
  - The message contains references to previous conversations
  - The message asks about past interactions
  - The message context would benefit from historical information
  - The conversation_id is present and not nil

  History is not needed when:
  - The message is self-contained
  - The message is a simple greeting or standalone query
  - No conversation_id is provided
  """

  @behaviour AgentCore.WorkflowEngine.Step

  @impl true
  def id, do: :assess_need

  @impl true
  def run(ctx, input, _opts) do
    current_message = Map.get(input, :current_message, "")
    conversation_id = Map.get(input, :conversation_id)

    needs_history = assess_need_for_history(current_message, conversation_id)

    updated_ctx =
      AgentCore.WorkflowEngine.Context.put_decision(ctx, :needs_history, needs_history)

    output = %{
      needs_history: needs_history,
      message_length: String.length(current_message),
      has_conversation_id: not is_nil(conversation_id)
    }

    {:ok, updated_ctx, output}
  end

  # Private function to determine if history is needed
  defp assess_need_for_history(message, conversation_id) do
    # If no conversation_id, we can't retrieve history anyway
    if is_nil(conversation_id) do
      false
    else
      # Check message content for indicators that history would be helpful
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
end
