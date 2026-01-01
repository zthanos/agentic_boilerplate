defmodule AgentRuntime.Llm.Plan.Steps.WorkflowHistoryStep do
  @moduledoc """
  Plan step that executes the history RAG workflow using the workflow engine.

  This step replaces the AssessNeedForHistoryStep by delegating to the
  workflow engine to execute the :history_rag workflow. It maintains
  backward compatibility with existing plan semantics while leveraging
  the new workflow system.
  """

  @behaviour AgentRuntime.Llm.Plan.Step

  require Logger

  alias AgentRuntime.Llm.Plan.PlanContext
  alias AgentRuntime.WorkflowEngine.PlanIntegration

  @impl true
  def name, do: "workflow_history"

  @impl true
  def run(%PlanContext{} = ctx, opts) do
    Logger.info("[plan] workflow_history step starting")

    # Extract workflow options from plan step options
    workflow_opts = Keyword.get(opts, :workflow_opts, %{})

    case PlanIntegration.run_workflow_with_context_update(ctx, :history_rag, workflow_opts) do
      {:cont, updated_ctx} ->
        Logger.info("[plan] workflow_history completed successfully")
        {:cont, updated_ctx}

      {:halt, {:error, reason}} ->
        Logger.error("[plan] workflow_history failed: #{inspect(reason)}")

        # Add debug information about the failure
        ctx_with_debug =
          PlanContext.add_debug(ctx, name(), %{
            "error" => inspect(reason),
            "workflow_id" => :history_rag,
            "failed_at" => DateTime.utc_now()
          })

        # For backward compatibility, continue with no history rather than halting
        # This matches the behavior of the original AssessNeedForHistoryStep
        fallback_ctx =
          ctx_with_debug
          |> PlanContext.put_decision(:needs_history, false)
          |> PlanContext.put_decision(:history_context, nil)
          |> PlanContext.put_decision(:history_items_used, 0)

        {:cont, fallback_ctx}
    end
  end
end
