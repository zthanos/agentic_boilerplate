defmodule AgentCore.Workflows do
  @moduledoc """
  Domain module for Workflows.

  A Workflow represents a structured execution flow with nodes, edges, and routing logic.
  This module contains the pure domain logic for workflows, including validation
  and specification management.
  """

  alias AgentCore.Workflows.{Spec, Context}

  @type workflow_id :: atom()
  @type node_id :: atom()
  @type predicate :: Spec.predicate()
  @type edge :: Spec.edge()
  @type node_spec :: Spec.node_spec()

  @doc """
  Creates a new workflow specification.

  ## Examples

      iex> AgentCore.Workflows.new_spec(
      ...>   id: :my_workflow,
      ...>   version: 1,
      ...>   entry: :start,
      ...>   exits: [:done, :error],
      ...>   nodes: %{
      ...>     start: %{step: MyApp.StartStep, opts: %{}},
      ...>     done: %{step: MyApp.DoneStep, opts: %{}}
      ...>   },
      ...>   edges: [
      ...>     %{from: :start, to: :done, when: {:always}}
      ...>   ]
      ...> )
      {:ok, %AgentCore.Workflows.Spec{...}}
  """
  @spec new_spec(keyword()) :: {:ok, Spec.t()} | {:error, [atom()]}
  def new_spec(attrs) do
    Spec.new(attrs)
  end

  @doc """
  Validates a workflow specification.
  """
  @spec validate_spec(Spec.t()) :: :ok | {:error, [atom()]}
  def validate_spec(%Spec{} = spec) do
    Spec.validate(spec)
  end

  @doc """
  Gets all node IDs in a workflow specification.
  """
  @spec node_ids(Spec.t()) :: [node_id()]
  def node_ids(%Spec{nodes: nodes}) do
    Map.keys(nodes)
  end

  @doc """
  Gets all exit node IDs in a workflow specification.
  """
  @spec exit_nodes(Spec.t()) :: [node_id()]
  def exit_nodes(%Spec{exits: exits}) do
    MapSet.to_list(exits)
  end

  @doc """
  Checks if a node is an exit node.
  """
  @spec exit_node?(Spec.t(), node_id()) :: boolean()
  def exit_node?(%Spec{exits: exits}, node_id) do
    MapSet.member?(exits, node_id)
  end

  @doc """
  Gets the entry node ID for a workflow.
  """
  @spec entry_node(Spec.t()) :: node_id()
  def entry_node(%Spec{entry: entry}), do: entry

  @doc """
  Gets all edges from a specific node.
  """
  @spec edges_from(Spec.t(), node_id()) :: [edge()]
  def edges_from(%Spec{edges: edges}, from_node) do
    Enum.filter(edges, fn %{from: from} -> from == from_node end)
  end

  @doc """
  Gets all edges to a specific node.
  """
  @spec edges_to(Spec.t(), node_id()) :: [edge()]
  def edges_to(%Spec{edges: edges}, to_node) do
    Enum.filter(edges, fn %{to: to} -> to == to_node end)
  end

  @doc """
  Checks if there's a direct path from one node to another.
  """
  @spec has_edge?(Spec.t(), node_id(), node_id()) :: boolean()
  def has_edge?(%Spec{edges: edges}, from_node, to_node) do
    Enum.any?(edges, fn %{from: from, to: to} ->
      from == from_node and to == to_node
    end)
  end

  @doc """
  Gets the step module and options for a node.
  """
  @spec node_step(Spec.t(), node_id()) :: {:ok, node_spec()} | {:error, :node_not_found}
  def node_step(%Spec{nodes: nodes}, node_id) do
    case Map.fetch(nodes, node_id) do
      {:ok, node_spec} -> {:ok, node_spec}
      :error -> {:error, :node_not_found}
    end
  end

  @doc """
  Creates a new workflow context for execution.
  """
  @spec new_context(map()) :: Context.t()
  def new_context(initial_data \\ %{}) do
    Context.new(initial_data)
  end

  @doc """
  Evaluates a predicate against a workflow context.
  """
  @spec evaluate_predicate(predicate(), Context.t()) :: boolean()
  def evaluate_predicate({:always}, _context), do: true

  def evaluate_predicate({:decision, key, expected_value}, context) do
    Context.get_decision(context, key) == expected_value
  end

  def evaluate_predicate({:artifact_present, key}, context) do
    Context.has_artifact?(context, key)
  end

  def evaluate_predicate({:custom, fun}, context) when is_function(fun, 1) do
    try do
      fun.(context)
    rescue
      _ -> false
    end
  end

  def evaluate_predicate(_, _), do: false

  @doc """
  Finds the next nodes to execute based on current node and context.
  """
  @spec next_nodes(Spec.t(), node_id(), Context.t()) :: [node_id()]
  def next_nodes(%Spec{} = spec, current_node, %Context{} = context) do
    spec
    |> edges_from(current_node)
    |> Enum.filter(fn %{when: predicate} ->
      evaluate_predicate(predicate, context)
    end)
    |> Enum.map(fn %{to: to} -> to end)
  end

  @doc """
  Checks if a workflow specification is well-formed.

  A well-formed workflow has:
  - All nodes reachable from entry
  - At least one path to an exit node
  - No orphaned nodes
  """
  @spec well_formed?(Spec.t()) :: boolean()
  def well_formed?(%Spec{} = spec) do
    with :ok <- validate_spec(spec),
         true <- all_nodes_reachable?(spec),
         true <- has_path_to_exit?(spec) do
      true
    else
      _ -> false
    end
  end

  # Private helpers

  defp all_nodes_reachable?(%Spec{} = spec) do
    reachable = find_reachable_nodes(spec, spec.entry, MapSet.new())
    all_nodes = MapSet.new(node_ids(spec))
    MapSet.equal?(reachable, all_nodes)
  end

  defp find_reachable_nodes(%Spec{} = spec, node, visited) do
    if MapSet.member?(visited, node) do
      visited
    else
      new_visited = MapSet.put(visited, node)

      spec
      |> edges_from(node)
      |> Enum.map(fn %{to: to} -> to end)
      |> Enum.reduce(new_visited, fn next_node, acc ->
        find_reachable_nodes(spec, next_node, acc)
      end)
    end
  end

  defp has_path_to_exit?(%Spec{} = spec) do
    exit_nodes = MapSet.new(exit_nodes(spec))

    # Check if any exit node is reachable from entry
    reachable = find_reachable_nodes(spec, spec.entry, MapSet.new())
    not MapSet.disjoint?(reachable, exit_nodes)
  end
end
