defmodule AgentRuntime.WorkflowEngine.PlanIntegrationTest do
  use ExUnit.Case, async: true

  alias AgentRuntime.WorkflowEngine.PlanIntegration
  alias AgentRuntime.Llm.Plan.PlanContext

  describe "convert_plan_to_workflow_input/2" do
    test "extracts current message and conversation_id from plan context" do
      plan_ctx = %PlanContext{
        profile: %{},
        overrides: %{},
        input: %{
          "messages" => [
            %{"role" => "system", "content" => "You are a helpful assistant"},
            %{"role" => "user", "content" => "What is the weather like?"},
            %{"role" => "assistant", "content" => "I can help with that."},
            %{"role" => "user", "content" => "Tell me about the project status"}
          ]
        },
        exec_meta: %{
          "conversation_id" => "conv_123",
          "trace_id" => "trace_456"
        }
      }

      {:ok, workflow_input} = PlanIntegration.convert_plan_to_workflow_input(plan_ctx)

      assert workflow_input.current_message == "Tell me about the project status"
      assert workflow_input.conversation_id == "conv_123"
    end

    test "handles missing conversation_id gracefully" do
      plan_ctx = %PlanContext{
        profile: %{},
        overrides: %{},
        input: %{
          "messages" => [
            %{"role" => "user", "content" => "Hello"}
          ]
        },
        exec_meta: %{}
      }

      {:ok, workflow_input} = PlanIntegration.convert_plan_to_workflow_input(plan_ctx)

      assert workflow_input.current_message == "Hello"
      assert workflow_input.conversation_id == nil
    end

    test "handles empty messages gracefully" do
      plan_ctx = %PlanContext{
        profile: %{},
        overrides: %{},
        input: %{"messages" => []},
        exec_meta: %{}
      }

      {:ok, workflow_input} = PlanIntegration.convert_plan_to_workflow_input(plan_ctx)

      assert workflow_input.current_message == ""
      assert workflow_input.conversation_id == nil
    end
  end

  describe "extract_workflow_output/1" do
    test "extracts final_output from workflow result" do
      workflow_result = %{
        status: :ok,
        final_output: %{
          history_context: "Previous discussion about project timeline",
          history_items_used: 3
        },
        visited_nodes: [:assess_need, :build_query, :retrieve_candidates, :compose_context, :done],
        trace: []
      }

      output = PlanIntegration.extract_workflow_output(workflow_result)

      assert output.history_context == "Previous discussion about project timeline"
      assert output.history_items_used == 3
    end

    test "handles nil final_output" do
      workflow_result = %{
        status: :ok,
        final_output: nil,
        visited_nodes: [:done],
        trace: []
      }

      output = PlanIntegration.extract_workflow_output(workflow_result)

      assert output == %{}
    end
  end

  describe "apply_workflow_results_to_plan_context/3" do
    test "updates plan context with history workflow results" do
      plan_ctx = %PlanContext{
        profile: %{},
        overrides: %{},
        input: %{},
        exec_meta: %{},
        decisions: %{},
        debug: []
      }

      workflow_output = %{
        history_context: "Previous discussion content",
        history_items_used: 2
      }

      updated_ctx =
        PlanIntegration.apply_workflow_results_to_plan_context(
          plan_ctx,
          workflow_output,
          :history_rag
        )

      assert updated_ctx.decisions[:needs_history] == true
      assert updated_ctx.decisions[:history_context] == "Previous discussion content"
      assert updated_ctx.decisions[:history_items_used] == 2

      # Check debug info was added
      assert length(updated_ctx.debug) == 1
      debug_entry = List.first(updated_ctx.debug)
      assert debug_entry.step == "workflow_execution"
      assert debug_entry.data["workflow_id"] == :history_rag
    end

    test "handles nil history_context" do
      plan_ctx = %PlanContext{
        profile: %{},
        overrides: %{},
        input: %{},
        exec_meta: %{},
        decisions: %{},
        debug: []
      }

      workflow_output = %{
        history_context: nil,
        history_items_used: 0
      }

      updated_ctx =
        PlanIntegration.apply_workflow_results_to_plan_context(
          plan_ctx,
          workflow_output,
          :history_rag
        )

      assert updated_ctx.decisions[:needs_history] == false
      assert updated_ctx.decisions[:history_context] == nil
      assert updated_ctx.decisions[:history_items_used] == 0
    end
  end
end
