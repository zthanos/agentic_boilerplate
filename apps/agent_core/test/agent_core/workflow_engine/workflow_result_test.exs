defmodule AgentCore.WorkflowEngine.WorkflowResultTest do
  use ExUnit.Case, async: true

  alias AgentCore.WorkflowEngine.WorkflowResult

  describe "success/3" do
    test "creates a successful workflow result" do
      final_output = %{data: "processed"}
      visited_nodes = [:start, :process, :done]
      trace = [%{node_id: :start, duration_ms: 10}]

      result = WorkflowResult.success(final_output, visited_nodes, trace)

      assert result.status == :ok
      assert result.final_output == final_output
      assert result.visited_nodes == visited_nodes
      assert result.trace == trace
      assert result.error == nil
    end
  end

  describe "failure/3" do
    test "creates a failed workflow result" do
      error = %{reason: :validation_error}
      visited_nodes = [:start]
      trace = [%{node_id: :start, duration_ms: 10}]

      result = WorkflowResult.failure(error, visited_nodes, trace)

      assert result.status == :failed
      assert result.final_output == nil
      assert result.visited_nodes == visited_nodes
      assert result.trace == trace
      assert result.error == error
    end
  end

  describe "error/3" do
    test "creates an error workflow result with defaults" do
      error = %{exception: "Invalid workflow spec"}

      result = WorkflowResult.error(error)

      assert result.status == :error
      assert result.final_output == nil
      assert result.visited_nodes == []
      assert result.trace == []
      assert result.error == error
    end

    test "creates an error workflow result with custom visited_nodes and trace" do
      error = %{exception: "Runtime error"}
      visited_nodes = [:start, :failed_node]
      trace = [%{node_id: :start, duration_ms: 5}]

      result = WorkflowResult.error(error, visited_nodes, trace)

      assert result.status == :error
      assert result.visited_nodes == visited_nodes
      assert result.trace == trace
      assert result.error == error
    end
  end
end
