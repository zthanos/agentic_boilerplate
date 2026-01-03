defmodule AgentRuntime.Workflows.StepExecutor do
  @moduledoc """
  Executes individual workflow steps.

  This module handles the execution of workflow steps, including:
  - Step module invocation
  - Error handling and recovery
  - Execution tracing
  - Timeout management
  """

  alias AgentCore.Workflows.Context
  require Logger

  @type step_result :: {:ok, Context.t()} | {:error, term()}
  @type step_module :: module()
  @type step_options :: map()

  @doc """
  Executes a workflow step.

  ## Parameters

  - `step_module` - The module implementing the step behavior
  - `context` - The current workflow context
  - `opts` - Step-specific options

  ## Returns

  - `{:ok, updated_context}` - Step executed successfully
  - `{:error, reason}` - Step execution failed
  """
  @spec execute_step(step_module(), Context.t(), step_options()) :: step_result()
  def execute_step(step_module, %Context{} = context, opts \\ %{}) do
    start_time = System.monotonic_time(:millisecond)

    Logger.debug("Executing workflow step",
      step_module: step_module,
      context_status: context.status
    )

    try do
      # Check if step module implements required behavior
      if not step_module_valid?(step_module) do
        {:error, {:invalid_step_module, step_module}}
      else
        # Execute the step
        case invoke_step(step_module, context, opts) do
          {:ok, updated_context} ->
            duration = System.monotonic_time(:millisecond) - start_time
            trace_step_execution(updated_context, step_module, :success, duration, opts)

          {:skip, updated_context} ->
            duration = System.monotonic_time(:millisecond) - start_time
            trace_step_execution(updated_context, step_module, :skipped, duration, opts)

          {:error, reason} ->
            duration = System.monotonic_time(:millisecond) - start_time
            failed_context = Context.mark_failed(context, reason)
            trace_step_execution(failed_context, step_module, :error, duration, opts)

          other ->
            duration = System.monotonic_time(:millisecond) - start_time
            reason = {:invalid_step_return, other}
            failed_context = Context.mark_failed(context, reason)
            trace_step_execution(failed_context, step_module, :error, duration, opts)
        end
      end
    rescue
      exception ->
        duration = System.monotonic_time(:millisecond) - start_time
        reason = {:step_exception, Exception.message(exception), __STACKTRACE__}

        Logger.error("Step execution failed with exception",
          step_module: step_module,
          exception: Exception.message(exception)
        )

        failed_context = Context.mark_failed(context, reason)
        trace_step_execution(failed_context, step_module, :error, duration, opts)
    end
  end

  @doc """
  Executes a step with timeout protection.
  """
  @spec execute_step_with_timeout(step_module(), Context.t(), step_options(), integer()) ::
          step_result()
  def execute_step_with_timeout(step_module, context, opts, timeout_ms) do
    task =
      Task.async(fn ->
        execute_step(step_module, context, opts)
      end)

    case Task.yield(task, timeout_ms) || Task.shutdown(task) do
      {:ok, result} ->
        result

      nil ->
        Logger.warning("Step execution timed out",
          step_module: step_module,
          timeout_ms: timeout_ms
        )

        {:error, {:step_timeout, timeout_ms}}
    end
  end

  # Private helper functions

  defp invoke_step(step_module, context, opts) do
    # Check if step module uses new or legacy interface
    if function_exported?(step_module, :execute, 2) do
      # New interface: execute(context, opts)
      step_module.execute(context, opts)
    else
      # Legacy interface: run(context, input, opts)
      # Extract input from context artifacts
      input = Context.get_artifact(context, :input, %{})

      case step_module.run(context, input, opts) do
        {:ok, updated_context, _output} -> {:ok, updated_context}
        {:skip, updated_context, _output} -> {:skip, updated_context}
        {:error, updated_context, error} -> {:error, error}
        other -> other
      end
    end
  end

  defp step_module_valid?(step_module) do
    # Check if module implements either new or legacy step interface
    function_exported?(step_module, :execute, 2) or
      function_exported?(step_module, :run, 3)
  end

  defp trace_step_execution(context, step_module, status, duration_ms, opts) do
    if Context.get_metadata(context, :trace_enabled, false) do
      trace_entry = %{
        type: :step_execution,
        step_module: step_module,
        status: status,
        duration_ms: duration_ms,
        options: opts,
        timestamp: DateTime.utc_now()
      }

      updated_context = Context.add_trace(context, trace_entry)

      case status do
        :success -> {:ok, updated_context}
        :skipped -> {:ok, updated_context}
        :error -> {:error, Context.get_metadata(updated_context, :error)}
      end
    else
      case status do
        :success -> {:ok, context}
        :skipped -> {:ok, context}
        :error -> {:error, Context.get_metadata(context, :error)}
      end
    end
  end
end
