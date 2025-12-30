defmodule AgentCore.Llm.AgentStore do
  @moduledoc "Agent storage contract (core). Implemented in agent_web (Ecto)."

  alias AgentCore.Llm.Agent.Definition

  @type agent_id :: Definition.id()
  @type version :: Definition.version()

  @callback get(agent_id(), version()) ::
              {:ok, Definition.t()} | {:error, :not_found} | {:error, term()}

  @callback get_latest(agent_id()) ::
              {:ok, Definition.t()} | {:error, :not_found} | {:error, term()}

  @callback put(Definition.t()) ::
              {:ok, Definition.t()} | {:error, term()}

  @callback list(keyword()) ::
              {:ok, [Definition.t()]} | {:error, term()}
end
