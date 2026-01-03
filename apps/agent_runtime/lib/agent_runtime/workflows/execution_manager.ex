defmodule AgentRuntime.Workflows.ExecutionManager do
  @moduledoc """
  Manages asynchronous workflow executions.

  This module provides functionality for:
  - Tracking active workflow executions
  - Managing execution state and lifecycle
  - Providing execution status and metrics
  - Handling execution cancellation
  """

  use GenServer
  require Logger

  alias AgentCore.Workflows.{Spec, Context}

  @type execution_id :: String.t()
  @type execution_status :: :running | :completed | :failed
  @type execution_entry :: %{
          id: execution_id(),
          task: Task.t(),
          spec: Spec.t(),
          context: Context.t(),
          status: execution_status(),
          started_at: DateTime.t(),
          completed_at: DateTime.t() | nil
        }

  # Client API

  @doc """
  Starts the ExecutionManager GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Registers a new async execution.
  """
  @spec register_execution(execution_id(), Task.t(), Spec.t(), Context.t()) :: :ok
  def register_execution(execution_id, task, spec, context) do
    GenServer.call(__MODULE__, {:register_execution, execution_id, task, spec, context})
  end

  @doc """
  Gets the status of an execution.
  """
  @spec get_execution_status(execution_id()) ::
          {:ok, execution_status(), Context.t()} | {:error, :not_found}
  def get_execution_status(execution_id) do
    GenServer.call(__MODULE__, {:get_status, execution_id})
  end

  @doc """
  Cancels an execution.
  """
  @spec cancel_execution(execution_id()) :: :ok | {:error, :not_found | :already_finished}
  def cancel_execution(execution_id) do
    GenServer.call(__MODULE__, {:cancel_execution, execution_id})
  end

  @doc """
  Lists all active executions.
  """
  @spec list_active_executions() :: {:ok, [execution_id()]} | {:error, term()}
  def list_active_executions do
    GenServer.call(__MODULE__, :list_active_executions)
  end

  @doc """
  Gets execution metrics.
  """
  @spec get_metrics(execution_id() | nil) :: {:ok, map()} | {:error, term()}
  def get_metrics(execution_id \\ nil) do
    GenServer.call(__MODULE__, {:get_metrics, execution_id})
  end

  # GenServer callbacks

  @impl true
  def init(_opts) do
    # Schedule periodic cleanup of completed executions
    Process.send_after(self(), :cleanup_completed, 60_000)

    state = %{
      executions: %{},
      metrics: %{
        total_started: 0,
        total_completed: 0,
        total_failed: 0,
        total_cancelled: 0
      }
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:register_execution, execution_id, task, spec, context}, _from, state) do
    execution_entry = %{
      id: execution_id,
      task: task,
      spec: spec,
      context: context,
      status: :running,
      started_at: DateTime.utc_now(),
      completed_at: nil
    }

    updated_executions = Map.put(state.executions, execution_id, execution_entry)
    updated_metrics = update_in(state.metrics, [:total_started], &(&1 + 1))

    new_state = %{state | executions: updated_executions, metrics: updated_metrics}

    # Monitor the task for completion
    Task.async(fn -> monitor_execution(execution_id, task) end)

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:get_status, execution_id}, _from, state) do
    case Map.get(state.executions, execution_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      execution_entry ->
        # Check if task is still running
        case Task.yield(execution_entry.task, 0) do
          nil ->
            # Still running
            {:reply, {:ok, :running, execution_entry.context}, state}

          {:ok, {:ok, final_context}} ->
            # Completed successfully
            {:reply, {:ok, :completed, final_context}, state}

          {:ok, {:error, reason}} ->
            # Failed
            failed_context = Context.mark_failed(execution_entry.context, reason)
            {:reply, {:ok, :failed, failed_context}, state}

          {:exit, reason} ->
            # Task exited
            failed_context = Context.mark_failed(execution_entry.context, {:task_exit, reason})
            {:reply, {:ok, :failed, failed_context}, state}
        end
    end
  end

  @impl true
  def handle_call({:cancel_execution, execution_id}, _from, state) do
    case Map.get(state.executions, execution_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      execution_entry ->
        if execution_entry.status != :running do
          {:reply, {:error, :already_finished}, state}
        else
          # Cancel the task
          Task.shutdown(execution_entry.task, :brutal_kill)

          # Update execution status
          updated_entry = %{
            execution_entry
            | status: :cancelled,
              completed_at: DateTime.utc_now()
          }

          updated_executions = Map.put(state.executions, execution_id, updated_entry)
          updated_metrics = update_in(state.metrics, [:total_cancelled], &(&1 + 1))

          new_state = %{state | executions: updated_executions, metrics: updated_metrics}

          {:reply, :ok, new_state}
        end
    end
  end

  @impl true
  def handle_call(:list_active_executions, _from, state) do
    active_ids =
      state.executions
      |> Enum.filter(fn {_id, entry} -> entry.status == :running end)
      |> Enum.map(fn {id, _entry} -> id end)

    {:reply, {:ok, active_ids}, state}
  end

  @impl true
  def handle_call({:get_metrics, execution_id}, _from, state) do
    if execution_id do
      # Get metrics for specific execution
      case Map.get(state.executions, execution_id) do
        nil ->
          {:reply, {:error, :not_found}, state}

        execution_entry ->
          metrics = %{
            execution_id: execution_id,
            workflow_id: execution_entry.spec.id,
            status: execution_entry.status,
            started_at: execution_entry.started_at,
            completed_at: execution_entry.completed_at,
            duration_ms: calculate_duration(execution_entry)
          }

          {:reply, {:ok, metrics}, state}
      end
    else
      # Get overall metrics
      overall_metrics =
        Map.merge(state.metrics, %{
          active_executions: count_active_executions(state.executions),
          total_executions: map_size(state.executions)
        })

      {:reply, {:ok, overall_metrics}, state}
    end
  end

  @impl true
  def handle_info(:cleanup_completed, state) do
    # Remove completed executions older than 1 hour
    cutoff_time = DateTime.add(DateTime.utc_now(), -3600, :second)

    updated_executions =
      state.executions
      |> Enum.reject(fn {_id, entry} ->
        entry.status != :running and
          entry.completed_at != nil and
          DateTime.compare(entry.completed_at, cutoff_time) == :lt
      end)
      |> Map.new()

    # Schedule next cleanup
    Process.send_after(self(), :cleanup_completed, 60_000)

    {:noreply, %{state | executions: updated_executions}}
  end

  @impl true
  def handle_info({:execution_completed, execution_id, result}, state) do
    case Map.get(state.executions, execution_id) do
      nil ->
        # Execution not found, ignore
        {:noreply, state}

      execution_entry ->
        {status, updated_metrics} =
          case result do
            {:ok, _final_context} ->
              {:completed, update_in(state.metrics, [:total_completed], &(&1 + 1))}

            {:error, _reason} ->
              {:failed, update_in(state.metrics, [:total_failed], &(&1 + 1))}
          end

        updated_entry = %{execution_entry | status: status, completed_at: DateTime.utc_now()}

        updated_executions = Map.put(state.executions, execution_id, updated_entry)

        new_state = %{state | executions: updated_executions, metrics: updated_metrics}

        {:noreply, new_state}
    end
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private helper functions

  defp monitor_execution(execution_id, task) do
    case Task.yield(task, :infinity) do
      {:ok, result} ->
        send(__MODULE__, {:execution_completed, execution_id, result})

      {:exit, reason} ->
        send(__MODULE__, {:execution_completed, execution_id, {:error, {:task_exit, reason}}})

      nil ->
        # This shouldn't happen with :infinity timeout
        send(__MODULE__, {:execution_completed, execution_id, {:error, :timeout}})
    end
  end

  defp count_active_executions(executions) do
    executions
    |> Enum.count(fn {_id, entry} -> entry.status == :running end)
  end

  defp calculate_duration(execution_entry) do
    if execution_entry.completed_at do
      DateTime.diff(execution_entry.completed_at, execution_entry.started_at, :millisecond)
    else
      DateTime.diff(DateTime.utc_now(), execution_entry.started_at, :millisecond)
    end
  end
end
