defmodule AgentCore.WorkflowEngine.CompilerTest do
  use ExUnit.Case, async: true
  alias AgentCore.WorkflowEngine.{Compiler, Spec}

  # Test step module
  defmodule TestStep do
    @behaviour AgentCore.WorkflowEngine.Step

    def id, do: :test_step

    def run(ctx, _input, _opts) do
      {:ok, ctx, %{result: "test"}}
    end
  end

  describe "workflow compilation" do
    test "compiles simple workflow successfully" do
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

      assert {:ok, execution_plan} = Compiler.compile(spec)
      assert execution_plan.workflow_id == :test_workflow
      assert execution_plan.version == 1
      assert execution_plan.entry_node == :start
      assert execution_plan.exit_nodes == [:finish]
      assert execution_plan.node_count == 2
      assert execution_plan.edge_count == 1
      assert is_map(execution_plan.execution_paths)
      assert is_map(execution_plan.optimizations)
      assert is_list(execution_plan.performance_hints)
      assert %DateTime{} = execution_plan.compiled_at
    end

    test "compiles workflow with optimizations" do
      spec = %Spec{
        id: :test_workflow,
        version: 1,
        entry: :start,
        nodes: %{
          start: %{step: TestStep, opts: %{}},
          middle: %{step: TestStep, opts: %{}},
          unreachable: %{step: TestStep, opts: %{}},
          finish: %{step: TestStep, opts: %{}}
        },
        edges: [
          %{from: :start, to: :middle, when: {:always}},
          %{from: :middle, to: :finish, when: {:always}}
        ],
        exits: MapSet.new([:finish])
      }

      assert {:ok, execution_plan} = Compiler.compile(spec, [:dead_code_elimination])
      assert execution_plan.optimizations.applied == [:dead_code_elimination]

      # The optimization should have removed the unreachable node, so node count should be 3 instead of 4
      assert execution_plan.node_count == 3
    end

    test "fails compilation for workflow with cycles" do
      spec = %Spec{
        id: :cyclic_workflow,
        version: 1,
        entry: :start,
        nodes: %{
          start: %{step: TestStep, opts: %{}},
          middle: %{step: TestStep, opts: %{}},
          finish: %{step: TestStep, opts: %{}}
        },
        edges: [
          %{from: :start, to: :middle, when: {:always}},
          # Creates cycle
          %{from: :middle, to: :start, when: {:always}},
          %{from: :middle, to: :finish, when: {:always}}
        ],
        exits: MapSet.new([:finish])
      }

      assert {:error, error_msg} = Compiler.compile(spec)
      assert String.contains?(error_msg, "Cycle detected")
    end

    test "fails compilation for workflow with unreachable exits" do
      spec = %Spec{
        id: :unreachable_workflow,
        version: 1,
        entry: :start,
        nodes: %{
          start: %{step: TestStep, opts: %{}},
          unreachable_exit: %{step: TestStep, opts: %{}}
        },
        edges: [],
        exits: MapSet.new([:start, :unreachable_exit])
      }

      assert {:error, error_msg} = Compiler.compile(spec)
      assert String.contains?(error_msg, "Unreachable exit nodes")
    end
  end

  describe "workflow optimization" do
    test "removes dead code" do
      spec = %Spec{
        id: :test_workflow,
        version: 1,
        entry: :start,
        nodes: %{
          start: %{step: TestStep, opts: %{}},
          reachable: %{step: TestStep, opts: %{}},
          unreachable1: %{step: TestStep, opts: %{}},
          unreachable2: %{step: TestStep, opts: %{}},
          finish: %{step: TestStep, opts: %{}}
        },
        edges: [
          %{from: :start, to: :reachable, when: {:always}},
          %{from: :reachable, to: :finish, when: {:always}},
          %{from: :unreachable1, to: :unreachable2, when: {:always}}
        ],
        exits: MapSet.new([:finish])
      }

      assert {:ok, result} = Compiler.optimize(spec, [:dead_code_elimination])

      # Should remove unreachable nodes
      assert map_size(result.optimized_spec.nodes) < map_size(result.original_spec.nodes)
      assert not Map.has_key?(result.optimized_spec.nodes, :unreachable1)
      assert not Map.has_key?(result.optimized_spec.nodes, :unreachable2)

      # Should remove edges to/from unreachable nodes
      assert length(result.optimized_spec.edges) < length(result.original_spec.edges)

      assert result.optimizations_applied == [:dead_code_elimination]
      assert result.performance_improvement.node_reduction > 0
    end

    test "optimizes edge order" do
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
          # Complex predicate
          %{from: :start, to: :branch1, when: {:custom, fn _ -> true end}},
          # Simple predicate
          %{from: :start, to: :branch2, when: {:always}},
          %{from: :branch1, to: :finish, when: {:always}},
          %{from: :branch2, to: :finish, when: {:always}}
        ],
        exits: MapSet.new([:finish])
      }

      assert {:ok, result} = Compiler.optimize(spec, [:path_optimization])

      # Should reorder edges (always predicates should come first for efficiency)
      start_edges = Enum.filter(result.optimized_spec.edges, &(&1.from == :start))
      assert length(start_edges) == 2

      # First edge should have simpler predicate
      first_edge = List.first(start_edges)
      assert match?(%{when: {:always}}, first_edge)
    end

    test "consolidates duplicate edges" do
      spec = %Spec{
        id: :test_workflow,
        version: 1,
        entry: :start,
        nodes: %{
          start: %{step: TestStep, opts: %{}},
          finish: %{step: TestStep, opts: %{}}
        },
        edges: [
          %{from: :start, to: :finish, when: {:always}},
          # Duplicate
          %{from: :start, to: :finish, when: {:always}},
          %{from: :start, to: :finish, when: {:decision, :test, true}}
        ],
        exits: MapSet.new([:finish])
      }

      assert {:ok, result} = Compiler.optimize(spec, [:edge_consolidation])

      # Should remove duplicate edges
      assert length(result.optimized_spec.edges) < length(result.original_spec.edges)
      assert result.performance_improvement.edge_reduction > 0
    end
  end

  describe "performance analysis" do
    test "analyzes simple workflow performance" do
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

      analysis = Compiler.analyze_performance(spec)

      assert is_integer(analysis.complexity_score)
      assert analysis.complexity_score > 0
      assert is_list(analysis.bottlenecks)
      assert is_list(analysis.optimization_hints)
      assert is_integer(analysis.estimated_execution_time)
      assert analysis.estimated_execution_time > 0
    end

    test "identifies bottlenecks in complex workflow" do
      spec = %Spec{
        id: :complex_workflow,
        version: 1,
        entry: :start,
        nodes: %{
          start: %{step: TestStep, opts: %{}},
          # High fan-out node
          hub: %{step: TestStep, opts: %{}},
          branch1: %{step: TestStep, opts: %{}},
          branch2: %{step: TestStep, opts: %{}},
          branch3: %{step: TestStep, opts: %{}},
          branch4: %{step: TestStep, opts: %{}},
          finish: %{step: TestStep, opts: %{}}
        },
        edges: [
          %{from: :start, to: :hub, when: {:always}},
          %{from: :hub, to: :branch1, when: {:decision, :choice, 1}},
          %{from: :hub, to: :branch2, when: {:decision, :choice, 2}},
          %{from: :hub, to: :branch3, when: {:decision, :choice, 3}},
          %{from: :hub, to: :branch4, when: {:decision, :choice, 4}},
          %{from: :branch1, to: :finish, when: {:always}},
          %{from: :branch2, to: :finish, when: {:always}},
          %{from: :branch3, to: :finish, when: {:always}},
          %{from: :branch4, to: :finish, when: {:always}}
        ],
        exits: MapSet.new([:finish])
      }

      analysis = Compiler.analyze_performance(spec)

      # Should identify hub as bottleneck due to high fan-out
      assert :hub in analysis.bottlenecks
      # Should be relatively complex
      assert analysis.complexity_score > 10
    end

    test "generates optimization hints for large workflows" do
      # Create a workflow with many nodes to trigger hints
      nodes =
        1..25
        |> Enum.map(&{:"node_#{&1}", %{step: TestStep, opts: %{}}})
        |> Enum.into(%{})

      edges =
        1..24
        |> Enum.map(&%{from: :"node_#{&1}", to: :"node_#{&1 + 1}", when: {:always}})

      spec = %Spec{
        id: :large_workflow,
        version: 1,
        entry: :node_1,
        nodes: nodes,
        edges: edges,
        exits: MapSet.new([:node_25])
      }

      analysis = Compiler.analyze_performance(spec)

      # Should suggest breaking up large workflow
      assert Enum.any?(
               analysis.optimization_hints,
               &String.contains?(&1, "breaking large workflow")
             )
    end
  end

  describe "validation" do
    test "validates workflow without cycles" do
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

      assert :ok = Compiler.validate_spec_for_compilation(spec)
    end

    test "detects cycles in workflow" do
      spec = %Spec{
        id: :cyclic_workflow,
        version: 1,
        entry: :start,
        nodes: %{
          start: %{step: TestStep, opts: %{}},
          middle: %{step: TestStep, opts: %{}},
          finish: %{step: TestStep, opts: %{}}
        },
        edges: [
          %{from: :start, to: :middle, when: {:always}},
          # Creates cycle
          %{from: :middle, to: :start, when: {:always}},
          %{from: :middle, to: :finish, when: {:always}}
        ],
        exits: MapSet.new([:finish])
      }

      assert {:error, error_msg} = Compiler.validate_spec_for_compilation(spec)
      assert String.contains?(error_msg, "Cycle detected")
    end

    test "validates reachability of exit nodes" do
      spec = %Spec{
        id: :unreachable_workflow,
        version: 1,
        entry: :start,
        nodes: %{
          start: %{step: TestStep, opts: %{}},
          unreachable_exit: %{step: TestStep, opts: %{}}
        },
        edges: [],
        exits: MapSet.new([:start, :unreachable_exit])
      }

      assert {:error, error_msg} = Compiler.validate_spec_for_compilation(spec)
      assert String.contains?(error_msg, "Unreachable exit nodes")
    end

    test "detects conflicting predicates" do
      spec = %Spec{
        id: :conflicting_workflow,
        version: 1,
        entry: :start,
        nodes: %{
          start: %{step: TestStep, opts: %{}},
          branch1: %{step: TestStep, opts: %{}},
          branch2: %{step: TestStep, opts: %{}}
        },
        edges: [
          %{from: :start, to: :branch1, when: {:always}},
          # Conflicting :always predicates
          %{from: :start, to: :branch2, when: {:always}}
        ],
        exits: MapSet.new([:branch1, :branch2])
      }

      assert {:error, error_msg} = Compiler.validate_spec_for_compilation(spec)
      assert String.contains?(error_msg, "Conflicting predicates")
    end
  end
end
