defmodule AgentCore.Tools.Behavior do
  @moduledoc """
  Behavior for tool implementations.

  This defines the contract that runtime implementations must follow
  for implementing tools that can be used by LLMs. Tools are discrete
  capabilities that can be invoked during conversations.
  """

  alias AgentCore.Tools.Spec

  @type tool_input :: map()
  @type tool_output :: map()
  @type tool_error :: term()
  @type execution_context :: map()

  @doc """
  Executes the tool with the given input.

  ## Parameters

  - `input` - The input parameters for the tool execution
  - `context` - Execution context containing metadata, configuration, etc.

  ## Returns

  - `{:ok, output}` - Tool executed successfully
  - `{:error, reason}` - Tool execution failed
  """
  @callback execute(tool_input(), execution_context()) ::
              {:ok, tool_output()} | {:error, tool_error()}

  @doc """
  Gets the tool specification.

  ## Returns

  - `spec` - The tool specification including schema and metadata
  """
  @callback spec() :: Spec.t()

  @doc """
  Validates tool input against the tool's parameter schema.

  ## Parameters

  - `input` - The input parameters to validate

  ## Returns

  - `:ok` - Input is valid
  - `{:error, reason}` - Input validation failed
  """
  @callback validate_input(tool_input()) :: :ok | {:error, tool_error()}

  @doc """
  Performs a health check on the tool.

  This can be used to verify that the tool's dependencies
  are available and the tool is ready for execution.

  ## Parameters

  - `context` - Execution context for the health check

  ## Returns

  - `:ok` - Tool is healthy and ready
  - `{:error, reason}` - Tool is not ready or has issues
  """
  @callback health_check(execution_context()) :: :ok | {:error, tool_error()}

  @doc """
  Gets usage statistics for the tool.

  ## Returns

  - `{:ok, stats}` - Tool usage statistics
  - `{:error, reason}` - Failed to get statistics
  """
  @callback usage_stats() :: {:ok, map()} | {:error, tool_error()}

  @optional_callbacks [
    validate_input: 1,
    health_check: 1,
    usage_stats: 0
  ]

  @doc """
  Executes a tool with automatic input validation.

  This is a helper function that validates input before execution.
  """
  @spec execute_with_validation(module(), tool_input(), execution_context()) ::
          {:ok, tool_output()} | {:error, tool_error()}
  def execute_with_validation(tool_module, input, context) do
    with :ok <- validate_tool_input(tool_module, input) do
      tool_module.execute(input, context)
    end
  end

  @doc """
  Validates tool input using the tool's validation function or spec.
  """
  @spec validate_tool_input(module(), tool_input()) :: :ok | {:error, tool_error()}
  def validate_tool_input(tool_module, input) do
    if function_exported?(tool_module, :validate_input, 1) do
      tool_module.validate_input(input)
    else
      # Fallback to basic spec-based validation
      spec = tool_module.spec()
      AgentCore.Tools.validate_input(spec, input)
    end
  end

  @doc """
  Gets the tool specification from a tool module.
  """
  @spec get_tool_spec(module()) :: Spec.t()
  def get_tool_spec(tool_module) do
    tool_module.spec()
  end

  @doc """
  Checks if a module implements the Tool behavior.
  """
  @spec tool_module?(module()) :: boolean()
  def tool_module?(module) do
    function_exported?(module, :execute, 2) and
      function_exported?(module, :spec, 0)
  end

  @doc """
  Creates a safe execution context with default values.
  """
  @spec default_context(map()) :: execution_context()
  def default_context(overrides \\ %{}) do
    %{
      timeout: 30_000,
      max_retries: 3,
      trace_enabled: false,
      user_id: nil,
      session_id: nil,
      request_id: nil
    }
    |> Map.merge(overrides)
  end

  @doc """
  Wraps tool execution with timeout and error handling.
  """
  @spec execute_with_timeout(module(), tool_input(), execution_context(), integer()) ::
          {:ok, tool_output()} | {:error, tool_error()}
  def execute_with_timeout(tool_module, input, context, timeout_ms) do
    task = Task.async(fn -> tool_module.execute(input, context) end)

    case Task.yield(task, timeout_ms) || Task.shutdown(task) do
      {:ok, result} -> result
      nil -> {:error, :timeout}
    end
  end

  @doc """
  Executes a tool with retry logic.
  """
  @spec execute_with_retry(module(), tool_input(), execution_context(), integer()) ::
          {:ok, tool_output()} | {:error, tool_error()}
  def execute_with_retry(tool_module, input, context, max_retries) do
    execute_with_retry_impl(tool_module, input, context, max_retries, 0)
  end

  # Private helpers

  defp execute_with_retry_impl(tool_module, input, context, max_retries, attempt) do
    case tool_module.execute(input, context) do
      {:ok, _} = success ->
        success

      {:error, reason} when attempt < max_retries ->
        # Add exponential backoff
        :timer.sleep(round(:math.pow(2, attempt) * 1000))
        execute_with_retry_impl(tool_module, input, context, max_retries, attempt + 1)

      {:error, _} = error ->
        error
    end
  end
end
