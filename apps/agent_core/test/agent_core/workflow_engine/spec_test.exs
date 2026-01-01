defmodule AgentCore.WorkflowEngine.SpecTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias AgentCore.WorkflowEngine.Spec

  # Test step modules for testing
  defmodule TestStep do
    @behaviour AgentCore.WorkflowEngine.Step
    def id, do: :test_step
    def run(ctx, _input, _opts), do: {:ok, ctx, %{}}
  end

  defmodule DoneStep do
    @behaviour AgentCore.WorkflowEngine.Step
    def id, do: :done_step
    def run(ctx, _input, _opts), do: {:ok, ctx, %{}}
  end

  describe "Spec struct" do
    test "creates valid spec with all required fields" do
      spec = %Spec{
        id: :test_workflow,
        version: 1,
        entry: :start,
        exits: MapSet.new([:done]),
        nodes: %{
          start: %{step: TestStep, opts: %{}},
          done: %{step: DoneStep, opts: %{}}
        },
        edges: [
          %{from: :start, to: :done, when: {:always}}
        ]
      }

      assert spec.id == :test_workflow
      assert spec.version == 1
      assert spec.entry == :start
      assert MapSet.member?(spec.exits, :done)
    end
  end

  describe "validation" do
    test "validates complete valid spec" do
      spec = %Spec{
        id: :test_workflow,
        version: 1,
        entry: :start,
        exits: MapSet.new([:done]),
        nodes: %{
          start: %{step: TestStep, opts: %{}},
          done: %{step: DoneStep, opts: %{}}
        },
        edges: [
          %{from: :start, to: :done, when: {:always}}
        ]
      }

      assert Spec.validate(spec) == :ok
    end

    test "fails validation for missing required fields" do
      spec = %Spec{}

      assert {:error, errors} = Spec.validate(spec)
      assert :missing_id in errors
      assert :missing_version in errors
      assert :missing_entry in errors
      assert :missing_nodes in errors
      assert :missing_edges in errors
      assert :missing_exits in errors
    end

    test "fails validation when entry node doesn't exist" do
      spec = %Spec{
        id: :test,
        version: 1,
        entry: :nonexistent,
        exits: MapSet.new([:done]),
        nodes: %{done: %{step: DoneStep, opts: %{}}},
        edges: []
      }

      assert {:error, errors} = Spec.validate(spec)
      assert :entry_node_not_found in errors
    end

    test "fails validation when exit nodes don't exist" do
      spec = %Spec{
        id: :test,
        version: 1,
        entry: :start,
        exits: MapSet.new([:nonexistent]),
        nodes: %{start: %{step: TestStep, opts: %{}}},
        edges: []
      }

      assert {:error, errors} = Spec.validate(spec)
      assert :exit_nodes_not_found in errors
    end

    test "fails validation for invalid edges" do
      spec = %Spec{
        id: :test,
        version: 1,
        entry: :start,
        exits: MapSet.new([:done]),
        nodes: %{start: %{step: TestStep, opts: %{}}},
        edges: [%{from: :start, to: :nonexistent, when: {:always}}]
      }

      assert {:error, errors} = Spec.validate(spec)
      assert :invalid_edges in errors
    end

    test "validates different predicate types" do
      spec = %Spec{
        id: :test,
        version: 1,
        entry: :start,
        exits: MapSet.new([:done]),
        nodes: %{
          start: %{step: TestStep, opts: %{}},
          done: %{step: DoneStep, opts: %{}}
        },
        edges: [
          %{from: :start, to: :done, when: {:always}},
          %{from: :start, to: :done, when: {:decision, :key, :value}},
          %{from: :start, to: :done, when: {:artifact_present, :key}},
          %{from: :start, to: :done, when: {:custom, fn _ctx -> true end}}
        ]
      }

      assert Spec.validate(spec) == :ok
    end

    test "fails validation for invalid predicates" do
      spec = %Spec{
        id: :test,
        version: 1,
        entry: :start,
        exits: MapSet.new([:done]),
        nodes: %{
          start: %{step: TestStep, opts: %{}},
          done: %{step: DoneStep, opts: %{}}
        },
        edges: [
          %{from: :start, to: :done, when: {:invalid_predicate}}
        ]
      }

      assert {:error, errors} = Spec.validate(spec)
      assert :invalid_predicates in errors
    end
  end

  describe "new/1" do
    test "creates valid spec from keyword list" do
      attrs = [
        id: :test,
        version: 1,
        entry: :start,
        exits: [:done],
        nodes: %{
          start: %{step: TestStep, opts: %{}},
          done: %{step: DoneStep, opts: %{}}
        },
        edges: [%{from: :start, to: :done, when: {:always}}]
      ]

      assert {:ok, spec} = Spec.new(attrs)
      assert spec.id == :test
      assert MapSet.member?(spec.exits, :done)
    end

    test "returns error for invalid spec" do
      attrs = [id: :test]

      assert {:error, errors} = Spec.new(attrs)
      assert is_list(errors)
      assert length(errors) > 0
    end

    test "handles exits as MapSet" do
      attrs = [
        id: :test,
        version: 1,
        entry: :start,
        exits: MapSet.new([:done]),
        nodes: %{
          start: %{step: TestStep, opts: %{}},
          done: %{step: DoneStep, opts: %{}}
        },
        edges: [%{from: :start, to: :done, when: {:always}}]
      ]

      assert {:ok, spec} = Spec.new(attrs)
      assert MapSet.member?(spec.exits, :done)
    end
  end

  # Property-based tests will be added in separate tasks
end
