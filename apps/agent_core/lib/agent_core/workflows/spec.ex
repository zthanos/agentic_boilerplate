defmodule AgentCore.Workflows.Spec do
  @moduledoc """
  Defines the structure and validation for workflow specifications.

  A workflow specification is a data structure that defines the topology, routing logic,
  and execution flow of a workflow. Workflows are defined as immutable specifications
  that can be validated, versioned, and stored.

  ## Structure

  A workflow specification contains:

  - `id` - Unique workflow identifier (atom)
  - `version` - Workflow version (integer)
  - `entry` - Entry node ID (atom)
  - `nodes` - Map of node IDs to step modules and options
  - `edges` - List of edges defining workflow routing
  - `exits` - Set of exit node IDs
  - `schema` - Optional input/output schemas for validation

  ## Example

      %AgentCore.Workflows.Spec{
        id: :my_workflow,
        version: 1,
        entry: :start,
        exits: MapSet.new([:done, :error]),
        nodes: %{
          start: %{step: MyApp.StartStep, opts: %{}},
          process: %{step: MyApp.ProcessStep, opts: %{timeout: 5000}},
          done: %{step: MyApp.DoneStep, opts: %{}}
        },
        edges: [
          %{from: :start, to: :process, when: {:always}},
          %{from: :process, to: :done, when: {:decision, :success, true}}
        ],
        schema: %{
          input: %{type: :map, required: [:data]},
          output: %{type: :map, required: [:result]}
        }
      }
  """

  defstruct [
    # atom() - unique workflow identifier
    :id,
    # integer() - workflow version
    :version,
    # atom() - entry node id
    :entry,
    # %{node_id => %{step: module(), opts: map()}}
    :nodes,
    # [%{from: atom(), to: atom(), when: predicate()}]
    :edges,
    # MapSet.t(atom()) - exit node ids
    :exits,
    # %{input: schema, output: schema} - optional
    :schema
  ]

  @type predicate ::
          {:always}
          | {:decision, atom(), term()}
          | {:artifact_present, atom()}
          | {:custom, function()}

  @type edge :: %{
          from: atom(),
          to: atom(),
          when: predicate()
        }

  @type node_spec :: %{
          step: module(),
          opts: map()
        }

  @type t :: %__MODULE__{
          id: atom(),
          version: integer(),
          entry: atom(),
          nodes: %{atom() => node_spec()},
          edges: [edge()],
          exits: MapSet.t(atom()),
          schema: map() | nil
        }

  @doc """
  Validates a workflow specification.

  Performs comprehensive validation including:
  - Required fields presence
  - Node ID uniqueness
  - Entry and exit node existence
  - Edge connectivity
  - Predicate format validation

  ## Examples

      iex> spec = %AgentCore.Workflows.Spec{
      ...>   id: :test,
      ...>   version: 1,
      ...>   entry: :start,
      ...>   exits: MapSet.new([:done]),
      ...>   nodes: %{start: %{step: TestStep, opts: %{}}, done: %{step: DoneStep, opts: %{}}},
      ...>   edges: [%{from: :start, to: :done, when: {:always}}]
      ...> }
      iex> AgentCore.Workflows.Spec.validate(spec)
      :ok

      iex> invalid_spec = %AgentCore.Workflows.Spec{id: :test}
      iex> AgentCore.Workflows.Spec.validate(invalid_spec)
      {:error, [:missing_version, :missing_entry, :missing_nodes, :missing_edges, :missing_exits]}
  """
  @spec validate(t()) :: :ok | {:error, [atom()]}
  def validate(%__MODULE__{} = spec) do
    errors =
      []
      |> validate_required_fields(spec)
      |> validate_entry_node_exists(spec)
      |> validate_exit_nodes_exist(spec)
      |> validate_edges(spec)
      |> validate_predicates(spec)

    case errors do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  @doc """
  Creates a new workflow specification with validation.

  ## Examples

      iex> AgentCore.Workflows.Spec.new(
      ...>   id: :test,
      ...>   version: 1,
      ...>   entry: :start,
      ...>   exits: [:done],
      ...>   nodes: %{start: %{step: TestStep, opts: %{}}, done: %{step: DoneStep, opts: %{}}},
      ...>   edges: [%{from: :start, to: :done, when: {:always}}]
      ...> )
      {:ok, %AgentCore.Workflows.Spec{...}}
  """
  @spec new(keyword()) :: {:ok, t()} | {:error, [atom()]}
  def new(attrs) do
    exits =
      case Keyword.get(attrs, :exits) do
        exits when is_list(exits) -> MapSet.new(exits)
        %MapSet{} = exits -> exits
        nil -> nil
      end

    spec = struct(__MODULE__, Keyword.put(attrs, :exits, exits))

    case validate(spec) do
      :ok -> {:ok, spec}
      error -> error
    end
  end

  # Private validation functions

  defp validate_required_fields(errors, spec) do
    required_fields = [:id, :version, :entry, :nodes, :edges, :exits]

    Enum.reduce(required_fields, errors, fn field, acc ->
      if Map.get(spec, field) == nil do
        [:"missing_#{field}" | acc]
      else
        acc
      end
    end)
  end

  defp validate_entry_node_exists(errors, %{entry: nil}), do: errors

  defp validate_entry_node_exists(errors, %{entry: _entry, nodes: nil}),
    do: [:entry_node_not_found | errors]

  defp validate_entry_node_exists(errors, %{entry: entry, nodes: nodes}) do
    if Map.has_key?(nodes, entry) do
      errors
    else
      [:entry_node_not_found | errors]
    end
  end

  defp validate_exit_nodes_exist(errors, %{exits: nil}), do: errors

  defp validate_exit_nodes_exist(errors, %{exits: _exits, nodes: nil}),
    do: [:exit_nodes_not_found | errors]

  defp validate_exit_nodes_exist(errors, %{exits: exits, nodes: nodes}) do
    missing_exits =
      exits
      |> MapSet.to_list()
      |> Enum.reject(&Map.has_key?(nodes, &1))

    if missing_exits == [] do
      errors
    else
      [:exit_nodes_not_found | errors]
    end
  end

  defp validate_edges(errors, %{edges: nil}), do: errors
  defp validate_edges(errors, %{edges: _edges, nodes: nil}), do: [:invalid_edges | errors]

  defp validate_edges(errors, %{edges: edges, nodes: nodes}) do
    invalid_edges =
      Enum.any?(edges, fn
        %{from: from, to: to} when is_atom(from) and is_atom(to) ->
          not (Map.has_key?(nodes, from) and Map.has_key?(nodes, to))

        _ ->
          true
      end)

    if invalid_edges do
      [:invalid_edges | errors]
    else
      errors
    end
  end

  defp validate_predicates(errors, %{edges: nil}), do: errors

  defp validate_predicates(errors, %{edges: edges}) do
    invalid_predicates =
      Enum.any?(edges, fn
        %{when: {:always}} -> false
        %{when: {:decision, key, _value}} when is_atom(key) -> false
        %{when: {:artifact_present, key}} when is_atom(key) -> false
        %{when: {:custom, fun}} when is_function(fun, 1) -> false
        _ -> true
      end)

    if invalid_predicates do
      [:invalid_predicates | errors]
    else
      errors
    end
  end
end
