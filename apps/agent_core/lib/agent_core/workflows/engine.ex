defmodule AgentCore.Workflows.Engine do
  @moduledoc """
  Behavior for workflow execution engines.

  This defines the contract that runtime implementations must follow
  for executing workflows. The behavior abstracts execution details
  and provides a uniform interface for workflow orchestration.
  """

  alias AgentCore.Workflows.{Spec, Context}

  @type execution_id :: String.t()
  @type execution_result :: {:ok, Context.t()} | {:error, term()}
  @type execution_options :: keyword()

  @doc """
  Executes a workflow specification with the given input context.

  ## Parameters

  - `spec` - The workflow specification to execute
  - `context` - The initial execution context with input data
  - `opts` - Execution options such as:
    - `:timeout` - Maximum execution time in milliseconds
    - `:max_steps` - Maximum number of steps to execute
    - `:trace` - Whether to enable detailed execution tracing
    - `:async` - Whether to execute asynchronously

  ## Returns

  - `{:ok, final_context}` - Workflow completed successfully
  - `{:error, reason}` - Workflow execution failed
  """
  @callback execute(Spec.t(), Context.t(), execution_options()) :: execution_result()

  @doc """
  Starts asynchronous execution of a workflow.

  ## Parameters

  - `spec` - The workflow specification to execute
  - `context` - The initial execution context with input data
  - `opts` - Execution options

  ## Returns

  - `{:ok, execution_id}` - Execution started successfully
  - `{:error, reason}` - Failed to start execution
  """
  @callback execute_async(Spec.t(), Context.t(), execution_options()) ::
              {:ok, execution_id()} | {:error, term()}

  @doc """
  Gets the status of an asynchronous execution.

  ## Parameters

  - `execution_id` - The execution identifier returned by execute_async/3

  ## Returns

  - `{:ok, :running, context}` - Execution is still running
  - `{:ok, :completed, context}` - Execution completed successfully
  - `{:ok, :failed, context}` - Execution failed
  - `{:error, :not_found}` - Execution not found
  - `{:error, reason}` - Status check failed
  """
  @callback execution_status(execution_id()) ::
              {:ok, :running | :completed | :failed, Context.t()}
              | {:error, :not_found | term()}

  @doc """
  Cancels an asynchronous execution.

  ## Parameters

  - `execution_id` - The execution identifier to cancel

  ## Returns

  - `:ok` - Execution cancelled successfully
  - `{:error, :not_found}` - Execution not found
  - `{:error, :already_finished}` - Execution already completed or failed
  - `{:error, reason}` - Cancellation failed
  """
  @callback cancel_execution(execution_id()) ::
              :ok | {:error, :not_found | :already_finished | term()}

  @doc """
  Validates a workflow specification for execution.

  ## Parameters

  - `spec` - The workflow specification to validate

  ## Returns

  - `:ok` - Specification is valid and executable
  - `{:error, reasons}` - Specification has validation errors
  """
  @callback validate_spec(Spec.t()) :: :ok | {:error, [atom()]}

  @doc """
  Compiles a workflow specification for optimized execution.

  This is an optional optimization step that can pre-process
  the specification for faster execution.

  ## Parameters

  - `spec` - The workflow specification to compile

  ## Returns

  - `{:ok, compiled_spec}` - Specification compiled successfully
  - `{:error, reason}` - Compilation failed
  """
  @callback compile_spec(Spec.t()) :: {:ok, term()} | {:error, term()}

  @doc """
  Lists all active executions.

  ## Returns

  - `{:ok, execution_ids}` - List of active execution identifiers
  - `{:error, reason}` - Failed to list executions
  """
  @callback list_executions() :: {:ok, [execution_id()]} | {:error, term()}

  @doc """
  Gets execution metrics and statistics.

  ## Parameters

  - `execution_id` - Optional specific execution to get metrics for

  ## Returns

  - `{:ok, metrics}` - Execution metrics
  - `{:error, reason}` - Failed to get metrics
  """
  @callback execution_metrics(execution_id() | nil) :: {:ok, map()} | {:error, term()}

  @optional_callbacks [
    execute_async: 3,
    execution_status: 1,
    cancel_execution: 1,
    compile_spec: 1,
    list_executions: 0,
    execution_metrics: 1
  ]

  @doc """
  Executes a single step within a workflow.

  This is a helper function that can be used by engine implementations
  to execute individual workflow steps.
  """
  @spec execute_step(module(), Context.t(), map()) :: {:ok, Context.t()} | {:error, term()}
  def execute_step(step_module, %Context{} = context, opts) when is_map(opts) do
    step_module.execute(context, opts)
  end

  @doc """
  Evaluates whether a workflow should transition to the next node.

  This is a helper function for engine implementations to evaluate
  workflow predicates and determine routing.
  """
  @spec should_transition?(Spec.predicate(), Context.t()) :: boolean()
  def should_transition?(predicate, %Context{} = context) do
    AgentCore.Workflows.evaluate_predicate(predicate, context)
  end

  @doc """
  Creates a new execution context with tracing enabled.
  """
  @spec new_traced_context(map()) :: Context.t()
  def new_traced_context(initial_data \\ %{}) do
    initial_data
    |> Context.new()
    |> Context.put_metadata(:trace_enabled, true)
    |> Context.put_metadata(:execution_start, DateTime.utc_now())
  end

  @doc """
  Adds an execution step to the context trace.
  """
  @spec trace_step(Context.t(), atom(), map()) :: Context.t()
  def trace_step(%Context{} = context, node_id, step_info) do
    trace_entry = %{
      type: :step_execution,
      node_id: node_id,
      step_info: step_info,
      timestamp: DateTime.utc_now()
    }

    Context.add_trace(context, trace_entry)
  end

  @doc """
  Adds a transition to the context trace.
  """
  @spec trace_transition(Context.t(), atom(), atom(), Spec.predicate()) :: Context.t()
  def trace_transition(%Context{} = context, from_node, to_node, predicate) do
    trace_entry = %{
      type: :transition,
      from_node: from_node,
      to_node: to_node,
      predicate: predicate,
      timestamp: DateTime.utc_now()
    }

    Context.add_trace(context, trace_entry)
  end
end
