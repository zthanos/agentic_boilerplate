# # lib/agent_runtime/llm/plan/step.ex
# defmodule AgentRuntime.Llm.Plan.Step do
#   @moduledoc """
#   Behaviour for plan steps.

#   - Return {:cont, ctx} to continue.
#   - Return {:halt, result} to stop early.
#   """

#   alias AgentRuntime.Llm.Plan.PlanContext

#   @type result ::
#           {:ok, %{mode: :executed, run_id: String.t(), trace_id: String.t()}}
#           | {:ok, %{mode: :needs_clarification, trace_id: String.t(), question: String.t()}}
#           | {:error, term()}

#   @callback name() :: String.t()
#   @callback run(PlanContext.t(), keyword()) :: {:cont, PlanContext.t()} | {:halt, result()}
# end
