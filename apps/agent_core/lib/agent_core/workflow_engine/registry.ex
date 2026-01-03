defmodule AgentCore.WorkflowEngine.Registry do
  @moduledoc """
  Registry for storing and managing workflow specifications.

  The Registry provides workflow validation, storage, and retrieval capabilities
  with security features like step module whitelisting.
  """

  use GenServer
  alias AgentCore.WorkflowEngine.Spec

  @type workflow_id :: atom() | String.t()
  @type validation_error :: {:error, String.t()}

  # Client API

  @doc """
  Starts the workflow registry.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Registers a workflow specification with validation.

  ## Examples

      iex> spec = %Spec{id: :test, version: 1, entry: :start, nodes: %{start: %{step: TestStep, opts: %{}}}, edges: [], exits: MapSet.new([:start])}
      iex> Registry.register_workflow(spec)
      :ok
  """
  @spec register_workflow(Spec.t()) :: :ok | validation_error()
  def register_workflow(%Spec{} = spec) do
    GenServer.call(__MODULE__, {:register_workflow, spec})
  end

  @doc """
  Retrieves a workflow specification by ID.

  ## Examples

      iex> Registry.get_workflow(:test)
      {:ok, %Spec{id: :test, ...}}

      iex> Registry.get_workflow(:nonexistent)
      {:error, "Workflow not found"}
  """
  @spec get_workflow(workflow_id()) :: {:ok, Spec.t()} | {:error, String.t()}
  def get_workflow(workflow_id) do
    GenServer.call(__MODULE__, {:get_workflow, workflow_id})
  end

  @doc """
  Lists all registered workflow IDs.
  """
  @spec list_workflows() :: [workflow_id()]
  def list_workflows do
    GenServer.call(__MODULE__, :list_workflows)
  end

  @doc """
  Validates a workflow specification without registering it.
  """
  @spec validate_workflow(Spec.t()) :: :ok | validation_error()
  def validate_workflow(%Spec{} = spec) do
    GenServer.call(__MODULE__, {:validate_workflow, spec})
  end

  @doc """
  Removes a workflow from the registry.
  """
  @spec unregister_workflow(workflow_id()) :: :ok | {:error, String.t()}
  def unregister_workflow(workflow_id) do
    GenServer.call(__MODULE__, {:unregister_workflow, workflow_id})
  end

  @doc """
  Clears all workflows from the registry (for testing purposes).
  """
  @spec clear_workflows() :: :ok
  def clear_workflows do
    GenServer.call(__MODULE__, :clear_workflows)
  end

  @doc """
  Compiles a workflow into an execution plan (optional optimization).
  """
  @spec compile_workflow(workflow_id()) :: {:ok, map()} | {:error, String.t()}
  def compile_workflow(workflow_id) do
    GenServer.call(__MODULE__, {:compile_workflow, workflow_id})
  end

  # Server Implementation

  @impl true
  def init(_opts) do
    {:ok, %{workflows: %{}, whitelisted_modules: get_whitelisted_modules()}}
  end

  @impl true
  def handle_call({:register_workflow, spec}, _from, state) do
    case validate_workflow_internal(spec, state.whitelisted_modules) do
      :ok ->
        new_workflows = Map.put(state.workflows, spec.id, spec)
        {:reply, :ok, %{state | workflows: new_workflows}}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:get_workflow, workflow_id}, _from, state) do
    case Map.get(state.workflows, workflow_id) do
      nil -> {:reply, {:error, "Workflow not found"}, state}
      spec -> {:reply, {:ok, spec}, state}
    end
  end

  @impl true
  def handle_call(:list_workflows, _from, state) do
    workflow_ids = Map.keys(state.workflows)
    {:reply, workflow_ids, state}
  end

  @impl true
  def handle_call({:validate_workflow, spec}, _from, state) do
    result = validate_workflow_internal(spec, state.whitelisted_modules)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:unregister_workflow, workflow_id}, _from, state) do
    case Map.has_key?(state.workflows, workflow_id) do
      true ->
        new_workflows = Map.delete(state.workflows, workflow_id)
        {:reply, :ok, %{state | workflows: new_workflows}}

      false ->
        {:reply, {:error, "Workflow not found"}, state}
    end
  end

  @impl true
  def handle_call(:clear_workflows, _from, state) do
    {:reply, :ok, %{state | workflows: %{}}}
  end

  @impl true
  def handle_call({:compile_workflow, workflow_id}, _from, state) do
    case Map.get(state.workflows, workflow_id) do
      nil ->
        {:reply, {:error, "Workflow not found"}, state}

      spec ->
        execution_plan = compile_execution_plan(spec)
        {:reply, {:ok, execution_plan}, state}
    end
  end

  # Private Functions

  defp validate_workflow_internal(%Spec{} = spec, whitelisted_modules) do
    with :ok <- validate_required_fields(spec),
         :ok <- validate_node_uniqueness(spec),
         :ok <- validate_entry_exists(spec),
         :ok <- validate_exits_exist(spec),
         :ok <- validate_edges_resolvable(spec),
         :ok <- validate_step_modules_whitelisted(spec, whitelisted_modules) do
      :ok
    end
  end

  defp validate_required_fields(%Spec{id: nil}), do: {:error, "Workflow ID is required"}
  defp validate_required_fields(%Spec{version: nil}), do: {:error, "Workflow version is required"}
  defp validate_required_fields(%Spec{entry: nil}), do: {:error, "Entry node is required"}

  defp validate_required_fields(%Spec{nodes: nodes}) when map_size(nodes) == 0,
    do: {:error, "At least one node is required"}

  defp validate_required_fields(%Spec{exits: exits}) when exits == %MapSet{},
    do: {:error, "At least one exit node is required"}

  defp validate_required_fields(_spec), do: :ok

  defp validate_node_uniqueness(%Spec{nodes: nodes}) do
    node_ids = Map.keys(nodes)
    unique_ids = Enum.uniq(node_ids)

    if length(node_ids) == length(unique_ids) do
      :ok
    else
      {:error, "Node IDs must be unique"}
    end
  end

  defp validate_entry_exists(%Spec{entry: entry, nodes: nodes}) do
    if Map.has_key?(nodes, entry) do
      :ok
    else
      {:error, "Entry node '#{entry}' does not exist in nodes"}
    end
  end

  defp validate_exits_exist(%Spec{exits: exits, nodes: nodes}) do
    missing_exits =
      exits
      |> MapSet.to_list()
      |> Enum.reject(&Map.has_key?(nodes, &1))

    if Enum.empty?(missing_exits) do
      :ok
    else
      {:error, "Exit nodes #{inspect(missing_exits)} do not exist in nodes"}
    end
  end

  defp validate_edges_resolvable(%Spec{edges: edges, nodes: nodes}) do
    invalid_edges =
      Enum.filter(edges, fn edge ->
        not (Map.has_key?(nodes, edge.from) and Map.has_key?(nodes, edge.to))
      end)

    if Enum.empty?(invalid_edges) do
      :ok
    else
      edge_descriptions = Enum.map(invalid_edges, fn edge -> "#{edge.from} -> #{edge.to}" end)

      {:error,
       "Invalid edges reference non-existent nodes: #{Enum.join(edge_descriptions, ", ")}"}
    end
  end

  defp validate_step_modules_whitelisted(%Spec{nodes: nodes}, whitelisted_modules) do
    invalid_modules =
      nodes
      |> Map.values()
      |> Enum.map(& &1.step)
      |> Enum.reject(&(&1 in whitelisted_modules))

    if Enum.empty?(invalid_modules) do
      :ok
    else
      {:error, "Step modules #{inspect(invalid_modules)} are not whitelisted"}
    end
  end

  defp compile_execution_plan(%Spec{} = spec) do
    %{
      workflow_id: spec.id,
      version: spec.version,
      entry_node: spec.entry,
      exit_nodes: MapSet.to_list(spec.exits),
      node_count: map_size(spec.nodes),
      edge_count: length(spec.edges),
      execution_paths: analyze_execution_paths(spec),
      compiled_at: DateTime.utc_now()
    }
  end

  defp analyze_execution_paths(%Spec{entry: entry, edges: edges, exits: exits}) do
    # Simple path analysis - could be enhanced for optimization
    reachable_nodes = find_reachable_nodes(entry, edges, MapSet.new())
    exit_list = MapSet.to_list(exits)

    %{
      reachable_from_entry: MapSet.to_list(reachable_nodes),
      unreachable_exits: Enum.reject(exit_list, &MapSet.member?(reachable_nodes, &1)),
      max_depth: calculate_max_depth(entry, edges, exits)
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

  defp get_whitelisted_modules do
    # Default whitelist - could be configurable via application environment
    [
      # Core workflow steps
      AgentCore.WorkflowEngine.Step,

      # History workflow steps
      AgentCore.WorkflowEngine.HistoryWorkflow.AssessNeedStep,
      AgentCore.WorkflowEngine.HistoryWorkflow.BuildQueryStep,
      AgentCore.WorkflowEngine.HistoryWorkflow.RetrieveCandidatesStep,
      AgentCore.WorkflowEngine.HistoryWorkflow.RerankCandidatesStep,
      AgentCore.WorkflowEngine.HistoryWorkflow.ComposeContextStep,
      AgentCore.WorkflowEngine.HistoryWorkflow.DoneStep,

      # RAG conversation workflow steps
      AgentCore.WorkflowEngine.RagConversationWorkflow.GenerateQueryStep,
      AgentCore.WorkflowEngine.RagConversationWorkflow.RetrieveContextStep,
      AgentCore.WorkflowEngine.RagConversationWorkflow.EnhancePromptStep,
      AgentCore.WorkflowEngine.RagConversationWorkflow.AssessClarificationStep,
      AgentCore.WorkflowEngine.RagConversationWorkflow.FinalResponseStep,
      AgentCore.WorkflowEngine.RagConversationWorkflow.CollectClarificationStep,

      # Test modules
      TestStep,
      MockStep,
      AgentCore.WorkflowEngine.RegistryTest.TestStep
    ]
  end
end
