defmodule AgentCore.WorkflowEngine.RegistryTest do
  use ExUnit.Case, async: false
  alias AgentCore.WorkflowEngine.{Registry, Spec}

  # Test step module for testing
  defmodule TestStep do
    @behaviour AgentCore.WorkflowEngine.Step

    def id, do: :test_step

    def run(ctx, _input, _opts) do
      {:ok, ctx, %{result: "test"}}
    end
  end

  setup do
    # Clear any existing workflows for clean test state
    # The Registry is already started by the application
    Registry.clear_workflows()
    :ok
  end

  describe "workflow registration" do
    test "registers valid workflow successfully" do
      spec = %Spec{
        id: :test_workflow,
        version: 1,
        entry: :start,
        nodes: %{
          start: %{step: TestStep, opts: %{}},
          finish: %{step: TestStep, opts: %{}}
        },
        edges: [
          %{from: :start, to: :finish, when: {:always}}
        ],
        exits: MapSet.new([:finish])
      }

      assert :ok = Registry.register_workflow(spec)
    end

    test "rejects workflow with missing required fields" do
      spec = %Spec{
        id: nil,
        version: 1,
        entry: :start,
        nodes: %{start: %{step: TestStep, opts: %{}}},
        edges: [],
        exits: MapSet.new([:start])
      }

      assert {:error, "Workflow ID is required"} = Registry.register_workflow(spec)
    end

    test "rejects workflow with non-existent entry node" do
      spec = %Spec{
        id: :test_workflow,
        version: 1,
        entry: :nonexistent,
        nodes: %{start: %{step: TestStep, opts: %{}}},
        edges: [],
        exits: MapSet.new([:start])
      }

      assert {:error, "Entry node 'nonexistent' does not exist in nodes"} =
               Registry.register_workflow(spec)
    end

    test "rejects workflow with non-existent exit nodes" do
      spec = %Spec{
        id: :test_workflow,
        version: 1,
        entry: :start,
        nodes: %{start: %{step: TestStep, opts: %{}}},
        edges: [],
        exits: MapSet.new([:nonexistent])
      }

      assert {:error, "Exit nodes [:nonexistent] do not exist in nodes"} =
               Registry.register_workflow(spec)
    end

    test "rejects workflow with invalid edges" do
      spec = %Spec{
        id: :test_workflow,
        version: 1,
        entry: :start,
        nodes: %{start: %{step: TestStep, opts: %{}}},
        edges: [
          %{from: :start, to: :nonexistent, when: {:always}}
        ],
        exits: MapSet.new([:start])
      }

      assert {:error, "Invalid edges reference non-existent nodes: start -> nonexistent"} =
               Registry.register_workflow(spec)
    end

    test "rejects workflow with non-whitelisted step modules" do
      defmodule UnwhitelistedStep do
        @behaviour AgentCore.WorkflowEngine.Step
        def id, do: :unwhitelisted
        def run(ctx, _input, _opts), do: {:ok, ctx, %{}}
      end

      spec = %Spec{
        id: :test_workflow,
        version: 1,
        entry: :start,
        nodes: %{start: %{step: UnwhitelistedStep, opts: %{}}},
        edges: [],
        exits: MapSet.new([:start])
      }

      assert {:error, error_msg} = Registry.register_workflow(spec)
      assert String.contains?(error_msg, "are not whitelisted")
    end
  end

  describe "workflow retrieval" do
    test "retrieves registered workflow" do
      spec = %Spec{
        id: :test_workflow,
        version: 1,
        entry: :start,
        nodes: %{start: %{step: TestStep, opts: %{}}},
        edges: [],
        exits: MapSet.new([:start])
      }

      :ok = Registry.register_workflow(spec)
      assert {:ok, retrieved_spec} = Registry.get_workflow(:test_workflow)
      assert retrieved_spec.id == :test_workflow
    end

    test "returns error for non-existent workflow" do
      assert {:error, "Workflow not found"} = Registry.get_workflow(:nonexistent)
    end
  end

  describe "workflow listing" do
    test "lists all registered workflows" do
      spec1 = %Spec{
        id: :workflow1,
        version: 1,
        entry: :start,
        nodes: %{start: %{step: TestStep, opts: %{}}},
        edges: [],
        exits: MapSet.new([:start])
      }

      spec2 = %Spec{
        id: :workflow2,
        version: 1,
        entry: :start,
        nodes: %{start: %{step: TestStep, opts: %{}}},
        edges: [],
        exits: MapSet.new([:start])
      }

      :ok = Registry.register_workflow(spec1)
      :ok = Registry.register_workflow(spec2)

      workflow_ids = Registry.list_workflows()
      assert :workflow1 in workflow_ids
      assert :workflow2 in workflow_ids
    end

    test "returns empty list when no workflows registered" do
      assert [] = Registry.list_workflows()
    end
  end

  describe "workflow validation" do
    test "validates workflow without registering" do
      spec = %Spec{
        id: :test_workflow,
        version: 1,
        entry: :start,
        nodes: %{start: %{step: TestStep, opts: %{}}},
        edges: [],
        exits: MapSet.new([:start])
      }

      assert :ok = Registry.validate_workflow(spec)
      assert {:error, "Workflow not found"} = Registry.get_workflow(:test_workflow)
    end
  end

  describe "workflow unregistration" do
    test "unregisters existing workflow" do
      spec = %Spec{
        id: :test_workflow,
        version: 1,
        entry: :start,
        nodes: %{start: %{step: TestStep, opts: %{}}},
        edges: [],
        exits: MapSet.new([:start])
      }

      :ok = Registry.register_workflow(spec)
      assert {:ok, _} = Registry.get_workflow(:test_workflow)

      assert :ok = Registry.unregister_workflow(:test_workflow)
      assert {:error, "Workflow not found"} = Registry.get_workflow(:test_workflow)
    end

    test "returns error when unregistering non-existent workflow" do
      assert {:error, "Workflow not found"} = Registry.unregister_workflow(:nonexistent)
    end
  end

  describe "workflow compilation" do
    test "compiles workflow into execution plan" do
      spec = %Spec{
        id: :test_workflow,
        version: 1,
        entry: :start,
        nodes: %{
          start: %{step: TestStep, opts: %{}},
          middle: %{step: TestStep, opts: %{}},
          finish: %{step: TestStep, opts: %{}}
        },
        edges: [
          %{from: :start, to: :middle, when: {:always}},
          %{from: :middle, to: :finish, when: {:always}}
        ],
        exits: MapSet.new([:finish])
      }

      :ok = Registry.register_workflow(spec)
      assert {:ok, execution_plan} = Registry.compile_workflow(:test_workflow)

      assert execution_plan.workflow_id == :test_workflow
      assert execution_plan.version == 1
      assert execution_plan.entry_node == :start
      assert execution_plan.exit_nodes == [:finish]
      assert execution_plan.node_count == 3
      assert execution_plan.edge_count == 2
      assert is_map(execution_plan.execution_paths)
      assert %DateTime{} = execution_plan.compiled_at
    end

    test "returns error when compiling non-existent workflow" do
      assert {:error, "Workflow not found"} = Registry.compile_workflow(:nonexistent)
    end

    test "analyzes execution paths correctly" do
      spec = %Spec{
        id: :test_workflow,
        version: 1,
        entry: :start,
        nodes: %{
          start: %{step: TestStep, opts: %{}},
          branch1: %{step: TestStep, opts: %{}},
          branch2: %{step: TestStep, opts: %{}},
          finish: %{step: TestStep, opts: %{}}
        },
        edges: [
          %{from: :start, to: :branch1, when: {:always}},
          %{from: :start, to: :branch2, when: {:always}},
          %{from: :branch1, to: :finish, when: {:always}}
        ],
        exits: MapSet.new([:finish, :branch2])
      }

      :ok = Registry.register_workflow(spec)
      assert {:ok, execution_plan} = Registry.compile_workflow(:test_workflow)

      paths = execution_plan.execution_paths
      assert :start in paths.reachable_from_entry
      assert :branch1 in paths.reachable_from_entry
      assert :branch2 in paths.reachable_from_entry
      assert :finish in paths.reachable_from_entry
      assert paths.unreachable_exits == []
      assert paths.max_depth >= 2
    end
  end
end
