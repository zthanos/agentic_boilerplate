defmodule AgentCore.Workflows.Step do
  @moduledoc """
  Defines the behavior for workflow steps.

  A step is a unit of work within a workflow that can be executed with a context
  and produces a result. Steps are the building blocks of workflows.
  """

  alias AgentCore.Workflows.Context

  @type step_result :: {:ok, Context.t()} | {:error, term()}
  @type step_opts :: map()

  @doc """
  Executes a workflow step with the given context and options.

  ## Parameters

  - `context` - The current workflow execution context
  - `opts` - Step-specific options from the workflow specification

  ## Returns

  - `{:ok, updated_context}` - Step completed successfully
  - `{:error, reason}` - Step failed with the given reason
  """
  @callback execute(Context.t(), step_opts()) :: step_result()

  @doc """
  Optional callback to validate step options at workflow compilation time.

  ## Parameters

  - `opts` - Step-specific options from the workflow specification

  ## Returns

  - `:ok` - Options are valid
  - `{:error, reason}` - Options are invalid
  """
  @callback validate_opts(step_opts()) :: :ok | {:error, term()}

  @optional_callbacks validate_opts: 1

  @doc """
  Executes a step module with the given context and options.
  """
  @spec execute_step(module(), Context.t(), step_opts()) :: step_result()
  def execute_step(step_module, %Context{} = context, opts) when is_map(opts) do
    step_module.execute(context, opts)
  end

  @doc """
  Validates step options if the step module implements the validate_opts callback.
  """
  @spec validate_step_opts(module(), step_opts()) :: :ok | {:error, term()}
  def validate_step_opts(step_module, opts) when is_map(opts) do
    if function_exported?(step_module, :validate_opts, 1) do
      step_module.validate_opts(opts)
    else
      :ok
    end
  end

  @doc """
  Checks if a module implements the Step behavior.
  """
  @spec step_module?(module()) :: boolean()
  def step_module?(module) do
    function_exported?(module, :execute, 2)
  end
end
