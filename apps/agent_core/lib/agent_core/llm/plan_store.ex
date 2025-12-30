defmodule AgentCore.Llm.PlanStore do
  @moduledoc "Plan storage contract (core). Implemented in agent_web (Ecto)."

  alias AgentCore.Llm.Plan.Definition

  @type plan_id :: Definition.id()
  @type version :: Definition.version()

  @callback get(plan_id(), version()) ::
              {:ok, Definition.t()} | {:error, :not_found} | {:error, term()}

  @callback get_latest(plan_id()) ::
              {:ok, Definition.t()} | {:error, :not_found} | {:error, term()}

  @callback put(Definition.t()) ::
              {:ok, Definition.t()} | {:error, term()}

  @callback list(keyword()) ::
              {:ok, [Definition.t()]} | {:error, term()}
end
