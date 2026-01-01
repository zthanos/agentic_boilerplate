defmodule AgentRuntime.Llm.Plan.Steps.WorkflowHistoryStepTest do
  use ExUnit.Case, async: true

  alias AgentRuntime.Llm.Plan.Steps.WorkflowHistoryStep
  alias AgentRuntime.Llm.Plan.PlanContext

  describe "name/0" do
    test "returns the correct step name" do
      assert WorkflowHistoryStep.name() == "workflow_history"
    end
  end

  describe "run/2" do
    test "returns fallback context when workflow execution fails" do
      # Create a plan context
      plan_ctx = %PlanContext{
        profile: %{},
        overrides: %{},
        input: %{
          "messages" => [
            %{"role" => "user", "content" => "What did we discuss earlier?"}
          ]
        },
        exec_meta: %{"conversation_id" => "conv_123"},
        decisions: %{},
        debug: []
      }

      # Run the step (this will fail because workflow registry isn't started in test)
      {:cont, result_ctx} = WorkflowHistoryStep.run(plan_ctx, [])

      # Should have fallback values
      assert result_ctx.decisions[:needs_history] == false
      assert result_ctx.decisions[:history_context] == nil
      assert result_ctx.decisions[:history_items_used] == 0

      # Should have debug information about the failure
      assert length(result_ctx.debug) == 1
      debug_entry = List.first(result_ctx.debug)
      assert debug_entry.step == "workflow_history"
      assert Map.has_key?(debug_entry.data, "error")
    end
  end
end
