# apps/agent_web/lib/agent_web/conversations/adapter.ex
defmodule AgentWeb.Conversations.Adapter do
  @behaviour AgentRuntime.Llm.Conversations

  alias AgentWeb.Conversations

  @impl true
  def ensure_conversation!(conversation_id, user_id) do
    try do
      Conversations.ensure_conversation!(conversation_id, user_id)
      :ok
    rescue
      e ->
        {:error, Exception.message(e)}
    end
  end

  @impl true
  def append_message!(conversation_id, role, content, run_id) do
    try do
      message = Conversations.append_message!(conversation_id, role, content, run_id)
      # ✅ Return the full message with all fields
      {:ok, message}
    rescue
      e ->
        {:error, Exception.message(e)}
    end
  end
end
