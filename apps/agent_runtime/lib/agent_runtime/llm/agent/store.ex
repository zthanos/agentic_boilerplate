defmodule AgentRuntime.Llm.Agent.Store do
  @moduledoc false

  def impl! do
    Application.fetch_env!(:agent_runtime, :agent_store)
  end
end
