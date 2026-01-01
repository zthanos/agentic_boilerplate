defmodule AgentCore.WorkflowEngine.HistoryWorkflowTest do
  use ExUnit.Case, async: true

  alias AgentCore.WorkflowEngine.{HistoryWorkflow, Spec}

  describe "workflow specification" do
    test "creates a valid workflow spec" do
      spec = HistoryWorkflow.spec()

      assert spec.id == :history_rag
      assert spec.version == 1
      assert spec.entry == :assess_need
      assert MapSet.member?(spec.exits, :done)

      # Validate the spec
      assert Spec.validate(spec) == :ok
    end

    test "has all required nodes" do
      spec = HistoryWorkflow.spec()

      required_nodes = [
        :assess_need,
        :build_query,
        :retrieve_candidates,
        :rerank_candidates,
        :compose_context,
        :done
      ]

      for node <- required_nodes do
        assert Map.has_key?(spec.nodes, node), "Missing node: #{node}"
      end
    end

    test "has valid edges" do
      spec = HistoryWorkflow.spec()

      # Check that all edges reference valid nodes
      for edge <- spec.edges do
        assert Map.has_key?(spec.nodes, edge.from), "Edge from invalid node: #{edge.from}"
        assert Map.has_key?(spec.nodes, edge.to), "Edge to invalid node: #{edge.to}"
      end
    end
  end

  describe "predicate functions" do
    test "candidates_not_empty returns true when candidates exist" do
      ctx = %{artifacts: %{history_candidates: [%{content: "test"}]}}
      assert HistoryWorkflow.candidates_not_empty(ctx) == true
    end

    test "candidates_not_empty returns false when candidates are empty" do
      ctx = %{artifacts: %{history_candidates: []}}
      assert HistoryWorkflow.candidates_not_empty(ctx) == false
    end

    test "candidates_not_empty returns false when candidates are nil" do
      ctx = %{artifacts: %{}}
      assert HistoryWorkflow.candidates_not_empty(ctx) == false
    end

    test "candidates_empty returns true when candidates are empty" do
      ctx = %{artifacts: %{history_candidates: []}}
      assert HistoryWorkflow.candidates_empty(ctx) == true
    end

    test "candidates_empty returns false when candidates exist" do
      ctx = %{artifacts: %{history_candidates: [%{content: "test"}]}}
      assert HistoryWorkflow.candidates_empty(ctx) == false
    end
  end

  describe "workflow metadata" do
    test "returns correct workflow ID" do
      assert HistoryWorkflow.workflow_id() == :history_rag
    end

    test "returns correct workflow version" do
      assert HistoryWorkflow.workflow_version() == 1
    end
  end
end
