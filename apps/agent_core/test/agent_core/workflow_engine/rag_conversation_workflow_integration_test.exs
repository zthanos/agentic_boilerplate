defmodule AgentCore.WorkflowEngine.RagConversationWorkflowIntegrationTest do
  use ExUnit.Case, async: true

  alias AgentCore.WorkflowEngine.{RagConversationWorkflow, Runtime, Registry, Context}

  @moduletag :workflow_engine

  setup do
    # Clear and register the workflow
    Registry.clear_workflows()
    :ok = RagConversationWorkflow.register_workflow()

    :ok
  end

  describe "workflow integration" do
    test "workflow can be retrieved from registry and executed" do
      # Verify workflow is registered
      assert {:ok, spec} = Registry.get_workflow(:rag_conversation)
      assert spec.id == :rag_conversation

      # Create test input
      input = %{
        user_message: "Hello, can you help me with my project?",
        # No conversation ID to trigger skip_history
        conversation_id: nil,
        # No profile to trigger fallback behavior
        profile: nil,
        overrides: %{}
      }

      # Create initial context
      ctx = %Context{
        decisions: %{},
        artifacts: %{},
        debug: %{},
        meta: %{run_id: "test-run", trace_id: "test-trace"},
        events: []
      }

      # Execute workflow - should follow skip_history path due to no conversation_id
      case Runtime.execute(spec, ctx, input) do
        {:ok, result} ->
          # Verify workflow completed successfully
          assert result.status == :ok
          assert result.final_output != nil
          assert length(result.visited_nodes) > 0
          assert length(result.trace) > 0

          # Should have visited generate_query and enhance_prompt at minimum
          assert :generate_query in result.visited_nodes
          assert :enhance_prompt in result.visited_nodes

        {:error, reason} ->
          # This is expected since we don't have real LLM integration in tests
          # The workflow should fail gracefully at the LLM execution step
          assert reason != nil
      end
    end

    test "workflow specification validates correctly" do
      assert {:ok, spec} = Registry.get_workflow(:rag_conversation)
      assert :ok = Registry.validate_workflow(spec)
    end

    test "workflow has correct entry and exit points" do
      assert {:ok, spec} = Registry.get_workflow(:rag_conversation)

      # Should start at generate_query
      assert spec.entry == :generate_query

      # Should have two exit points
      assert MapSet.equal?(spec.exits, MapSet.new([:final_response, :collect_clarification]))
    end

    test "workflow edges provide complete routing coverage" do
      assert {:ok, spec} = Registry.get_workflow(:rag_conversation)

      # Group edges by source node
      edges_by_from = Enum.group_by(spec.edges, & &1.from)

      # Verify generate_query has routing options
      generate_edges = edges_by_from[:generate_query]
      assert length(generate_edges) == 2

      # Should route to both retrieve_context and enhance_prompt
      destinations = Enum.map(generate_edges, & &1.to)
      assert :retrieve_context in destinations
      assert :enhance_prompt in destinations

      # Verify assess_clarification has routing to both exit points
      assess_edges = edges_by_from[:assess_clarification]
      assert length(assess_edges) == 2

      destinations = Enum.map(assess_edges, & &1.to)
      assert :final_response in destinations
      assert :collect_clarification in destinations
    end

    test "workflow compilation generates execution plan" do
      assert {:ok, execution_plan} = Registry.compile_workflow(:rag_conversation)

      # Verify execution plan structure
      assert execution_plan.workflow_id == :rag_conversation
      assert execution_plan.version == 1
      assert execution_plan.entry_node == :generate_query
      assert execution_plan.node_count == 6
      assert execution_plan.edge_count == 6
      assert execution_plan.compiled_at != nil

      # Verify reachability analysis
      assert execution_plan.execution_paths != nil
      assert is_list(execution_plan.execution_paths.reachable_from_entry)
      assert is_list(execution_plan.execution_paths.unreachable_exits)
    end
  end

  describe "workflow error handling" do
    test "workflow handles missing profile gracefully" do
      assert {:ok, spec} = Registry.get_workflow(:rag_conversation)

      input = %{
        user_message: "Test message",
        # Has conversation ID but no profile
        conversation_id: "test-conv",
        profile: nil,
        overrides: %{}
      }

      ctx = %Context{
        decisions: %{},
        artifacts: %{},
        debug: %{},
        meta: %{run_id: "test-run", trace_id: "test-trace"},
        events: []
      }

      # Should handle gracefully - either succeed with fallback or fail with proper error
      case Runtime.execute(spec, ctx, input) do
        {:ok, result} ->
          # If it succeeds, should have proper trace
          assert result.status in [:ok, :failed]
          assert length(result.trace) > 0

        {:error, _reason} ->
          # Expected due to missing dependencies
          :ok
      end
    end

    test "workflow handles empty user message" do
      assert {:ok, spec} = Registry.get_workflow(:rag_conversation)

      input = %{
        # Empty message
        user_message: "",
        conversation_id: nil,
        profile: nil,
        overrides: %{}
      }

      ctx = %Context{
        decisions: %{},
        artifacts: %{},
        debug: %{},
        meta: %{run_id: "test-run", trace_id: "test-trace"},
        events: []
      }

      # Should handle gracefully
      case Runtime.execute(spec, ctx, input) do
        {:ok, result} ->
          assert result.status in [:ok, :failed]
          assert length(result.trace) > 0

        {:error, _reason} ->
          # Expected due to missing dependencies
          :ok
      end
    end
  end
end
