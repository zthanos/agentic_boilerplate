defmodule AgentRuntime.Workflows.Engine do
  @moduledoc """
  Runtime implementation of the workflow execution engine.

  This module implements the AgentCore.Workflows.Engine behavior and provides
  the actual workflow execution logic. It handles:
  - Synchronous and asynchronous workflow execution
  - Node traversal and step execution
  - Edge predicate evaluation
  - Execution state management
  - Error handling and recovery
  """

  @behaviour AgentCore.Workflows.Engine

  alias AgentCore.Workflows.{Spec, Context}
  alias AgentRuntime.Workflows.{ExecutionManager, StepExecutor}

  require Logger

  @impl true
  def execute(%Spec{} = spec, %Context{} = context, opts \\ []) do
    Logger.info("Starting workflow execution", workflow_id: spec.id, version: spec.version)

    with :ok <- Spec.validate(spec) do
      # Initialize execution state
      execution_context = prepare_execution_context(context, spec, opts)

      # Execute workflow synchronously
      case execute_workflow_sync(spec, execution_context, opts) do
        {:ok, final_context} ->
          Logger.info("Workflow execution completed successfully", workflow_id: spec.id)
          {:ok, final_context}

        {:error, reason} ->
          Logger.error("Workflow execution failed",
            workflow_id: spec.id,
            reason: inspect(reason)
          )

          {:error, reason}
      end
    else
      {:error, validation_errors} ->
        Logger.error("Workflow validation failed",
          workflow_id: spec.id,
          errors: validation_errors
        )

        {:error, {:validation_failed, validation_errors}}
    end
  end

  @impl true
  def execute_async(%Spec{} = spec, %Context{} = context, opts \\ []) do
    execution_id = generate_execution_id()

    Logger.info("Starting async workflow execution",
      workflow_id: spec.id,
      execution_id: execution_id
    )

    # Start async execution
    task =
      Task.async(fn ->
        execute(spec, context, opts)
      end)

    # Register execution for tracking
    ExecutionManager.register_execution(execution_id, task, spec, context)

    {:ok, execution_id}
  end

  @impl true
  def execution_status(execution_id) do
    case ExecutionManager.get_execution_status(execution_id) do
      {:ok, status, context} -> {:ok, status, context}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def cancel_execution(execution_id) do
    case ExecutionManager.cancel_execution(execution_id) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def validate_spec(%Spec{} = spec) do
    Spec.validate(spec)
  end

  @impl true
  def compile_spec(%Spec{} = spec) do
    # For now, return the spec as-is
    # Future optimization: pre-compute execution paths, validate step modules, etc.
    {:ok, spec}
  end

  @impl true
  def list_executions do
    ExecutionManager.list_active_executions()
  end

  @impl true
  def execution_metrics(execution_id \\ nil) do
    ExecutionManager.get_metrics(execution_id)
  end

  # Private implementation functions

  defp execute_workflow_sync(%Spec{} = spec, %Context{} = context, opts) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    max_steps = Keyword.get(opts, :max_steps, 1000)

    try do
      execute_from_node(spec, context, spec.entry, [], max_steps)
    catch
      :timeout -> {:error, :execution_timeout}
      {:max_steps_exceeded, steps} -> {:error, {:max_steps_exceeded, steps}}
    after
      # Cleanup any resources if needed
      :ok
    end
  end

  defp execute_from_node(
         %Spec{} = spec,
         %Context{} = context,
         current_node,
         visited_nodes,
         max_steps
       ) do
    # Check for infinite loop protection
    if length(visited_nodes) >= max_steps do
      throw({:max_steps_exceeded, length(visited_nodes)})
    end

    # Add current node to visited list
    updated_visited = [current_node | visited_nodes]

    # Check if we've reached an exit node
    if MapSet.member?(spec.exits, current_node) do
      # Execute exit node and return
      execute_exit_node(spec, context, current_node)
    else
      # Execute current node and continue to next
      case execute_node(spec, context, current_node) do
        {:ok, updated_context} ->
          case resolve_next_node(spec, updated_context, current_node) do
            {:ok, next_node} ->
              execute_from_node(spec, updated_context, next_node, updated_visited, max_steps)

            {:error, reason} ->
              {:error, {:transition_failed, current_node, reason}}
          end

        {:error, reason} ->
          {:error, {:node_execution_failed, current_node, reason}}
      end
    end
  end

  defp execute_exit_node(%Spec{} = spec, %Context{} = context, exit_node) do
    case execute_node(spec, context, exit_node) do
      {:ok, final_context} ->
        # Mark context as completed
        completed_context = Context.mark_completed(final_context)
        {:ok, completed_context}

      {:error, reason} ->
        # Mark context as failed
        failed_context = Context.mark_failed(context, reason)
        {:error, failed_context}
    end
  end

  defp execute_node(%Spec{} = spec, %Context{} = context, node_id) do
    case Map.get(spec.nodes, node_id) do
      nil ->
        {:error, {:node_not_found, node_id}}

      %{step: step_module, opts: step_opts} ->
        StepExecutor.execute_step(step_module, context, step_opts)
    end
  end

  defp resolve_next_node(%Spec{} = spec, %Context{} = context, current_node) do
    # Find all outgoing edges from current node
    outgoing_edges =
      Enum.filter(spec.edges, fn edge ->
        edge.from == current_node
      end)

    case outgoing_edges do
      [] ->
        {:error, :no_outgoing_edges}

      edges ->
        # Find first matching edge (deterministic order)
        case find_matching_edge(edges, context) do
          nil -> {:error, :no_matching_edges}
          edge -> {:ok, edge.to}
        end
    end
  end

  defp find_matching_edge(edges, %Context{} = context) do
    Enum.find(edges, fn edge ->
      evaluate_predicate(edge.when, context)
    end)
  end

  defp evaluate_predicate({:always}, _context), do: true

  defp evaluate_predicate({:decision, key, expected_value}, %Context{} = context) do
    actual_value = Context.get_decision(context, key)
    actual_value == expected_value
  end

  defp evaluate_predicate({:artifact_present, key}, %Context{} = context) do
    Context.has_artifact?(context, key)
  end

  defp evaluate_predicate({:custom, predicate_fn}, %Context{} = context)
       when is_function(predicate_fn, 1) do
    try do
      predicate_fn.(context)
    rescue
      _ -> false
    end
  end

  defp evaluate_predicate(_predicate, _context), do: false

  defp prepare_execution_context(%Context{} = context, %Spec{} = spec, opts) do
    context
    |> Context.put_metadata(:workflow_id, spec.id)
    |> Context.put_metadata(:workflow_version, spec.version)
    |> Context.put_metadata(:execution_start, DateTime.utc_now())
    |> Context.put_metadata(:execution_options, opts)
    |> maybe_enable_tracing(opts)
  end

  defp maybe_enable_tracing(%Context{} = context, opts) do
    if Keyword.get(opts, :trace, false) do
      Context.put_metadata(context, :trace_enabled, true)
    else
      context
    end
  end

  defp generate_execution_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
