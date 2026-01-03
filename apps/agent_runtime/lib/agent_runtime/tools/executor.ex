defmodule AgentRuntime.Tools.Executor do
  @moduledoc """
  Executes tool implementations.

  This module provides the runtime execution logic for tools,
  including validation, execution, and error handling.
  """

  alias AgentCore.Tools.Behavior
  alias AgentRuntime.Tools.Registry

  require Logger

  @type tool_name :: String.t() | atom()
  @type tool_input :: map()
  @type execution_context :: map()
  @type tool_result :: {:ok, map()} | {:error, term()}

  @doc """
  Executes a tool by name.

  ## Parameters

  - `tool_name` - The name of the tool to execute
  - `input` - Input parameters for the tool
  - `context` - Execution context

  ## Returns

  - `{:ok, output}` - Tool executed successfully
  - `{:error, reason}` - Tool execution failed
  """
  @spec execute_tool(tool_name(), tool_input(), execution_context()) :: tool_result()
  def execute_tool(tool_name, input, context \\ %{}) do
    Logger.info("Executing tool", tool_name: tool_name)

    with {:ok, tool_module} <- Registry.get_tool(tool_name),
         {:ok, validated_input} <- validate_tool_input(tool_module, input),
         {:ok, execution_context} <- prepare_execution_context(context) do
      execute_tool_module(tool_module, validated_input, execution_context)
    else
      {:error, reason} ->
        Logger.error("Tool execution failed",
          tool_name: tool_name,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  @doc """
  Executes a tool module directly.

  ## Parameters

  - `tool_module` - The tool module to execute
  - `input` - Input parameters for the tool
  - `context` - Execution context

  ## Returns

  - `{:ok, output}` - Tool executed successfully
  - `{:error, reason}` - Tool execution failed
  """
  @spec execute_tool_module(module(), tool_input(), execution_context()) :: tool_result()
  def execute_tool_module(tool_module, input, context) do
    timeout = Map.get(context, :timeout, 30_000)

    Logger.debug("Executing tool module",
      module: tool_module,
      timeout: timeout
    )

    try do
      case Behavior.execute_with_timeout(tool_module, input, context, timeout) do
        {:ok, output} ->
          Logger.debug("Tool execution completed successfully", module: tool_module)
          {:ok, output}

        {:error, reason} ->
          Logger.warning("Tool execution failed",
            module: tool_module,
            reason: inspect(reason)
          )

          {:error, reason}
      end
    rescue
      exception ->
        Logger.error("Tool execution raised exception",
          module: tool_module,
          exception: Exception.message(exception)
        )

        {:error, {:tool_exception, Exception.message(exception)}}
    end
  end

  @doc """
  Executes a tool with retry logic.
  """
  @spec execute_tool_with_retry(tool_name(), tool_input(), execution_context(), integer()) ::
          tool_result()
  def execute_tool_with_retry(tool_name, input, context, max_retries \\ 3) do
    execute_tool_with_retry_impl(tool_name, input, context, max_retries, 0)
  end

  @doc """
  Gets the specification for a tool.
  """
  @spec get_tool_spec(tool_name()) :: {:ok, map()} | {:error, term()}
  def get_tool_spec(tool_name) do
    with {:ok, tool_module} <- Registry.get_tool(tool_name) do
      spec = Behavior.get_tool_spec(tool_module)
      {:ok, spec}
    end
  end

  @doc """
  Validates tool input against its specification.
  """
  @spec validate_tool_input(module(), tool_input()) :: {:ok, tool_input()} | {:error, term()}
  def validate_tool_input(tool_module, input) do
    case Behavior.validate_tool_input(tool_module, input) do
      :ok -> {:ok, input}
      {:error, reason} -> {:error, {:input_validation_failed, reason}}
    end
  end

  @doc """
  Performs a health check on a tool.
  """
  @spec health_check_tool(tool_name(), execution_context()) :: :ok | {:error, term()}
  def health_check_tool(tool_name, context \\ %{}) do
    with {:ok, tool_module} <- Registry.get_tool(tool_name) do
      if function_exported?(tool_module, :health_check, 1) do
        tool_module.health_check(context)
      else
        :ok
      end
    end
  end

  # Private helper functions

  defp execute_tool_with_retry_impl(tool_name, input, context, max_retries, attempt) do
    case execute_tool(tool_name, input, context) do
      {:ok, _} = success ->
        success

      {:error, reason} when attempt < max_retries ->
        Logger.info("Retrying tool execution",
          tool_name: tool_name,
          attempt: attempt + 1,
          max_retries: max_retries
        )

        # Add exponential backoff
        :timer.sleep(round(:math.pow(2, attempt) * 1000))
        execute_tool_with_retry_impl(tool_name, input, context, max_retries, attempt + 1)

      {:error, _} = error ->
        error
    end
  end

  defp prepare_execution_context(context) do
    default_context = Behavior.default_context()
    merged_context = Map.merge(default_context, context)

    # Add execution metadata
    execution_context =
      Map.merge(merged_context, %{
        execution_id: generate_execution_id(),
        started_at: DateTime.utc_now()
      })

    {:ok, execution_context}
  end

  defp generate_execution_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
