# apps/agent_runtime/lib/agent_runtime/conversations/behavior.ex
defmodule AgentRuntime.Llm.Conversations do
  @callback ensure_conversation!(binary(), binary()) :: :ok | {:error, any()}
  @callback append_message!(binary(), String.t(), String.t(), binary() | nil) ::
              {:ok, map()} | {:error, any()}
end
