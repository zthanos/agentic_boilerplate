defmodule AgentCore.WorkflowEngine.Compiler do
  @moduledoc """
  Workflow compilation and optimization utilities.

  This module provides advanced compilation features including execution plan
  generation, workflow optimization, and performance analysis tools.
  """

  alias AgentCore.WorkflowEngine.Spec

  @type execution_plan :: %{
          workflow_id: atom() | String.t(),
          version: integer(),
          entry_node: atom(),
          exit_nodes: [atom()],
          node_count: integer(),
          edge_count: integer(),
          execution_paths: map(),
          optimizations: map(),
          performance_hints: [String.t()],
          compiled_at: DateTime.t()
        }

  @type optimization_result :: %{
          original_spec: Spec.t(),
          optimized_spec: Spec.t(),
          optimizations_applied: [atom()],
          performance_improvement: map()
        }

  @doc """
  Compiles a workflow specification into an optimized execution plan.

  ## Examples

      iex> spec = %Spec{...}
      iex> Compiler.compile(spec, [:dead_code_elimination, :path_optimization])
      {:ok, %{workflow_id: :test, optimizations: %{...}}}
  """
  @spec compile(Spec.t(), [atom()]) :: {:ok, execution_plan()} | {:error, String.t()}
  def compile(%Spec{} = spec, optimizations \\ []) do
    with :ok <- validate_spec_for_compilation(spec),
         {:ok, optimized_spec} <- apply_optimizations(spec, optimizations),
         execution_plan <- generate_execution_plan(optimized_spec, optimizations) do
      {:ok, execution_plan}
    end
  end

  @doc """
  Optimizes a workflow specification by applying various optimization techniques.

  Available optimizations:
  - `:dead_code_elimination` - Removes unreachable nodes
  - `:path_optimization` - Optimizes execution paths
  - `:edge_consolidation` - Consolidates redundant edges
  - `:predicate_optimization` - Optimizes predicate evaluation order
  """
  @spec optimize(Spec.t(), [atom()]) :: {:ok, optimization_result()} | {:error, String.t()}
  def optimize(
        %Spec{} = original_spec,
        optimizations \\ [:dead_code_elimination, :path_optimization]
      ) do
    with {:ok, optimized_spec} <- apply_optimizations(original_spec, optimizations) do
      result = %{
        original_spec: original_spec,
        optimized_spec: optimized_spec,
        optimizations_applied: optimizations,
        performance_improvement: calculate_performance_improvement(original_spec, optimized_spec)
      }

      {:ok, result}
    end
  end

  @doc """
  Analyzes workflow performance characteristics and provides optimization hints.
  """
  @spec analyze_performance(Spec.t()) :: %{
          complexity_score: integer(),
          bottlenecks: [atom()],
          optimization_hints: [String.t()],
          estimated_execution_time: integer()
        }
  def analyze_performance(%Spec{} = spec) do
    %{
      complexity_score: calculate_complexity_score(spec),
      bottlenecks: identify_bottlenecks(spec),
      optimization_hints: generate_optimization_hints(spec),
      estimated_execution_time: estimate_execution_time(spec)
    }
  end

  @doc """
  Validates that a workflow specification can be safely compiled.
  """
  @spec validate_spec_for_compilation(Spec.t()) :: :ok | {:error, String.t()}
  def validate_spec_for_compilation(%Spec{} = spec) do
    with :ok <- check_for_cycles(spec),
         :ok <- validate_reachability(spec),
         :ok <- validate_predicate_consistency(spec) do
      :ok
    end
  end

  # Private Functions

  defp apply_optimizations(spec, optimizations) do
    Enum.reduce_while(optimizations, {:ok, spec}, fn optimization, {:ok, current_spec} ->
      case apply_single_optimization(current_spec, optimization) do
        {:ok, optimized_spec} -> {:cont, {:ok, optimized_spec}}
        error -> {:halt, error}
      end
    end)
  end

  defp apply_single_optimization(spec, :dead_code_elimination) do
    reachable_nodes = find_reachable_nodes(spec.entry, spec.edges, MapSet.new())

    unreachable_nodes =
      spec.nodes
      |> Map.keys()
      |> Enum.reject(&MapSet.member?(reachable_nodes, &1))

    if Enum.empty?(unreachable_nodes) do
      {:ok, spec}
    else
      optimized_nodes = Map.drop(spec.nodes, unreachable_nodes)

      optimized_edges =
        Enum.reject(spec.edges, fn edge ->
          edge.from in unreachable_nodes or edge.to in unreachable_nodes
        end)

      {:ok, %{spec | nodes: optimized_nodes, edges: optimized_edges}}
    end
  end

  defp apply_single_optimization(spec, :path_optimization) do
    # Optimize by reordering edges for better performance
    optimized_edges = optimize_edge_order(spec.edges)
    {:ok, %{spec | edges: optimized_edges}}
  end

  defp apply_single_optimization(spec, :edge_consolidation) do
    # Consolidate edges with identical predicates
    consolidated_edges = consolidate_duplicate_edges(spec.edges)
    {:ok, %{spec | edges: consolidated_edges}}
  end

  defp apply_single_optimization(spec, :predicate_optimization) do
    # Optimize predicate evaluation order (most selective first)
    optimized_edges = optimize_predicate_order(spec.edges)
    {:ok, %{spec | edges: optimized_edges}}
  end

  defp apply_single_optimization(_spec, unknown_optimization) do
    {:error, "Unknown optimization: #{unknown_optimization}"}
  end

  defp generate_execution_plan(spec, applied_optimizations) do
    paths = analyze_execution_paths(spec)
    performance_analysis = analyze_performance(spec)

    %{
      workflow_id: spec.id,
      version: spec.version,
      entry_node: spec.entry,
      exit_nodes: MapSet.to_list(spec.exits),
      node_count: map_size(spec.nodes),
      edge_count: length(spec.edges),
      execution_paths: paths,
      optimizations: %{
        applied: applied_optimizations,
        dead_code_removed: paths.unreachable_nodes,
        optimization_score: calculate_optimization_score(spec, applied_optimizations)
      },
      performance_hints: performance_analysis.optimization_hints,
      compiled_at: DateTime.utc_now()
    }
  end

  defp analyze_execution_paths(%Spec{entry: entry, edges: edges, exits: exits, nodes: nodes}) do
    reachable_nodes = find_reachable_nodes(entry, edges, MapSet.new())
    all_nodes = MapSet.new(Map.keys(nodes))
    unreachable_nodes = MapSet.difference(all_nodes, reachable_nodes)

    %{
      reachable_from_entry: MapSet.to_list(reachable_nodes),
      unreachable_nodes: MapSet.to_list(unreachable_nodes),
      unreachable_exits: Enum.reject(MapSet.to_list(exits), &MapSet.member?(reachable_nodes, &1)),
      max_depth: calculate_max_depth(entry, edges, exits),
      branching_factor: calculate_branching_factor(edges),
      critical_path: find_critical_path(entry, edges, exits)
    }
  end

  defp find_reachable_nodes(current, edges, visited) do
    if MapSet.member?(visited, current) do
      visited
    else
      new_visited = MapSet.put(visited, current)

      edges
      |> Enum.filter(&(&1.from == current))
      |> Enum.reduce(new_visited, fn edge, acc ->
        find_reachable_nodes(edge.to, edges, acc)
      end)
    end
  end

  defp calculate_max_depth(entry, edges, exits, depth \\ 0, visited \\ MapSet.new()) do
    if MapSet.member?(exits, entry) or MapSet.member?(visited, entry) do
      depth
    else
      new_visited = MapSet.put(visited, entry)

      next_nodes =
        edges
        |> Enum.filter(&(&1.from == entry))
        |> Enum.map(& &1.to)

      if Enum.empty?(next_nodes) do
        depth
      else
        next_nodes
        |> Enum.map(&calculate_max_depth(&1, edges, exits, depth + 1, new_visited))
        |> Enum.max()
      end
    end
  end

  defp calculate_branching_factor(edges) do
    edges
    |> Enum.group_by(& &1.from)
    |> Map.values()
    |> Enum.map(&length/1)
    |> case do
      [] -> 0
      factors -> Enum.sum(factors) / length(factors)
    end
  end

  defp find_critical_path(entry, edges, exits) do
    # Simple critical path analysis - could be enhanced
    paths = find_all_paths_to_exits(entry, edges, exits, [entry])

    case paths do
      [] -> []
      _ -> Enum.max_by(paths, &length/1)
    end
  end

  defp find_all_paths_to_exits(current, edges, exits, current_path) do
    if MapSet.member?(exits, current) do
      [current_path]
    else
      next_nodes =
        edges
        |> Enum.filter(&(&1.from == current))
        |> Enum.map(& &1.to)
        # Avoid cycles
        |> Enum.reject(&(&1 in current_path))

      next_nodes
      |> Enum.flat_map(&find_all_paths_to_exits(&1, edges, exits, current_path ++ [&1]))
    end
  end

  defp calculate_complexity_score(%Spec{nodes: nodes, edges: edges}) do
    # Simple complexity scoring based on nodes and edges
    node_count = map_size(nodes)
    edge_count = length(edges)
    branching_complexity = calculate_branching_complexity(edges)

    node_count + edge_count * 2 + branching_complexity * 3
  end

  defp calculate_branching_complexity(edges) do
    edges
    |> Enum.group_by(& &1.from)
    |> Map.values()
    |> Enum.map(&length/1)
    |> Enum.filter(&(&1 > 1))
    |> Enum.sum()
  end

  defp identify_bottlenecks(%Spec{edges: edges}) do
    # Identify nodes with high fan-in or fan-out
    fan_out =
      Enum.group_by(edges, & &1.from) |> Enum.map(fn {node, edges} -> {node, length(edges)} end)

    fan_in =
      Enum.group_by(edges, & &1.to) |> Enum.map(fn {node, edges} -> {node, length(edges)} end)

    high_fan_out =
      Enum.filter(fan_out, fn {_node, count} -> count > 3 end) |> Enum.map(&elem(&1, 0))

    high_fan_in =
      Enum.filter(fan_in, fn {_node, count} -> count > 3 end) |> Enum.map(&elem(&1, 0))

    (high_fan_out ++ high_fan_in) |> Enum.uniq()
  end

  defp generate_optimization_hints(%Spec{} = spec) do
    hints = []

    hints =
      if map_size(spec.nodes) > 20 do
        ["Consider breaking large workflow into smaller sub-workflows" | hints]
      else
        hints
      end

    hints =
      if length(spec.edges) > 50 do
        ["High edge count may impact performance - consider simplifying routing logic" | hints]
      else
        hints
      end

    bottlenecks = identify_bottlenecks(spec)

    hints =
      if length(bottlenecks) > 0 do
        [
          "Bottleneck nodes detected: #{Enum.join(bottlenecks, ", ")} - consider optimization"
          | hints
        ]
      else
        hints
      end

    Enum.reverse(hints)
  end

  defp estimate_execution_time(%Spec{} = spec) do
    # Simple estimation based on complexity
    # Base execution time in ms
    base_time = 10
    node_time = map_size(spec.nodes) * 5
    edge_time = length(spec.edges) * 2
    complexity_penalty = calculate_complexity_score(spec) * 0.5

    round(base_time + node_time + edge_time + complexity_penalty)
  end

  defp calculate_performance_improvement(original_spec, optimized_spec) do
    original_complexity = calculate_complexity_score(original_spec)
    optimized_complexity = calculate_complexity_score(optimized_spec)

    %{
      complexity_reduction: original_complexity - optimized_complexity,
      node_reduction: map_size(original_spec.nodes) - map_size(optimized_spec.nodes),
      edge_reduction: length(original_spec.edges) - length(optimized_spec.edges),
      estimated_speedup: calculate_estimated_speedup(original_spec, optimized_spec)
    }
  end

  defp calculate_estimated_speedup(original_spec, optimized_spec) do
    original_time = estimate_execution_time(original_spec)
    optimized_time = estimate_execution_time(optimized_spec)

    if optimized_time > 0 do
      original_time / optimized_time
    else
      1.0
    end
  end

  defp calculate_optimization_score(spec, applied_optimizations) do
    base_score = 100
    complexity_penalty = calculate_complexity_score(spec) * 0.1
    optimization_bonus = length(applied_optimizations) * 10

    max(0, round(base_score - complexity_penalty + optimization_bonus))
  end

  defp optimize_edge_order(edges) do
    # Sort edges by predicate complexity (simpler predicates first)
    Enum.sort_by(edges, &predicate_complexity/1)
  end

  defp predicate_complexity(%{when: {:always}}), do: 1
  defp predicate_complexity(%{when: {:decision, _key, _value}}), do: 2
  defp predicate_complexity(%{when: {:artifact_present, _key}}), do: 3
  defp predicate_complexity(%{when: {:custom, _function}}), do: 4
  defp predicate_complexity(_), do: 5

  defp consolidate_duplicate_edges(edges) do
    # Remove duplicate edges (same from, to, and when)
    Enum.uniq(edges)
  end

  defp optimize_predicate_order(edges) do
    # Group edges by from node and sort by predicate selectivity
    edges
    |> Enum.group_by(& &1.from)
    |> Enum.flat_map(fn {_from, node_edges} ->
      Enum.sort_by(node_edges, &predicate_selectivity/1)
    end)
  end

  # Always matches, should be last
  defp predicate_selectivity(%{when: {:always}}), do: 0
  # Moderately selective
  defp predicate_selectivity(%{when: {:decision, _key, _value}}), do: 3
  # More selective
  defp predicate_selectivity(%{when: {:artifact_present, _key}}), do: 2
  # Most selective (assumed)
  defp predicate_selectivity(%{when: {:custom, _function}}), do: 1
  defp predicate_selectivity(_), do: 4

  # Validation functions

  defp check_for_cycles(%Spec{entry: entry, edges: edges}) do
    case detect_cycle(entry, edges, MapSet.new(), []) do
      nil -> :ok
      cycle -> {:error, "Cycle detected: #{Enum.join(cycle, " -> ")}"}
    end
  end

  defp detect_cycle(current, edges, visited, path) do
    if current in path do
      Enum.drop_while(path, &(&1 != current)) ++ [current]
    else
      if MapSet.member?(visited, current) do
        nil
      else
        new_visited = MapSet.put(visited, current)
        new_path = [current | path]

        next_nodes =
          edges
          |> Enum.filter(&(&1.from == current))
          |> Enum.map(& &1.to)

        Enum.find_value(next_nodes, fn next_node ->
          detect_cycle(next_node, edges, new_visited, new_path)
        end)
      end
    end
  end

  defp validate_reachability(%Spec{entry: entry, exits: exits, edges: edges}) do
    reachable_nodes = find_reachable_nodes(entry, edges, MapSet.new())

    unreachable_exits =
      exits
      |> MapSet.to_list()
      |> Enum.reject(&MapSet.member?(reachable_nodes, &1))

    if Enum.empty?(unreachable_exits) do
      :ok
    else
      {:error, "Unreachable exit nodes: #{Enum.join(unreachable_exits, ", ")}"}
    end
  end

  defp validate_predicate_consistency(%Spec{edges: edges}) do
    # Check for conflicting predicates from the same node
    conflicts =
      edges
      |> Enum.group_by(& &1.from)
      |> Enum.filter(fn {_from, node_edges} ->
        has_conflicting_predicates?(node_edges)
      end)
      |> Enum.map(&elem(&1, 0))

    if Enum.empty?(conflicts) do
      :ok
    else
      {:error, "Conflicting predicates detected for nodes: #{Enum.join(conflicts, ", ")}"}
    end
  end

  defp has_conflicting_predicates?(edges) do
    # Simple check: if there's an :always predicate, it should be the only one or last
    always_edges = Enum.filter(edges, &match?(%{when: {:always}}, &1))

    length(always_edges) > 1 or (length(always_edges) == 1 and length(edges) > 1)
  end
end
