defmodule AgentCore.WorkflowEngine.WorkflowResult do
  @moduledoc """
  Represents the result of a workflow execution.

  The WorkflowResult contains all information about a completed workflow execution,
  including the final status, output, execution path, and detailed trace information.

  ## Structure

  - `status` - Execution status (:ok, :failed, :error)
  - `final_output` - The final output from the workflow
  - `visited_nodes` - List of nodes visited during execution
  - `trace` - Detailed execution trace with timing and debug information
  - `error` - Error details if status is not :ok

  ## Usage

      # Successful workflow result
      %AgentCore.WorkflowEngine.WorkflowResult{
        status: :ok,
        final_output: %{result: "processed_data"},
        visited_nodes: [:start, :process, :done],
        trace: [%{node_id: :start, duration_ms: 10, ...}, ...],
        error: nil
      }

      # Failed workflow result
      %AgentCore.WorkflowEngine.WorkflowResult{
        status: :failed,
        final_output: nil,
        visited_nodes: [:start, :process],
        trace: [%{node_id: :start, duration_ms: 10, ...}, ...],
        error: %{reason: :validation_failed, step: :process}
      }
  """

  defstruct [
    # :ok | :failed | :error
    :status,
    # map() - normalized workflow output
    :final_output,
    # [atom()] - execution path
    :visited_nodes,
    # [map()] - detailed execution trace
    :trace,
    # term() - error details if status != :ok
    :error
  ]

  @type status :: :ok | :failed | :error

  @type trace_entry :: %{
          node_id: atom(),
          step_module: module(),
          status: :ok | :skip | :error,
          duration_ms: integer(),
          input_keys: [atom()],
          output_keys: [atom()],
          error: term() | nil
        }

  @type t :: %__MODULE__{
          status: status(),
          final_output: map() | nil,
          visited_nodes: [atom()],
          trace: [trace_entry()],
          error: term() | nil
        }

  @doc """
  Creates a successful workflow result.

  ## Examples

      iex> result = AgentCore.WorkflowEngine.WorkflowResult.success(
      ...>   %{data: "processed"},
      ...>   [:start, :done],
      ...>   [%{node_id: :start, duration_ms: 10}]
      ...> )
      iex> result.status
      :ok
  """
  @spec success(map(), [atom()], [trace_entry()]) :: t()
  def success(final_output, visited_nodes, trace) do
    %__MODULE__{
      status: :ok,
      final_output: final_output,
      visited_nodes: visited_nodes,
      trace: trace,
      error: nil
    }
  end

  @doc """
  Creates a failed workflow result.

  ## Examples

      iex> result = AgentCore.WorkflowEngine.WorkflowResult.failure(
      ...>   %{reason: :validation_error},
      ...>   [:start],
      ...>   [%{node_id: :start, duration_ms: 10}]
      ...> )
      iex> result.status
      :failed
  """
  @spec failure(term(), [atom()], [trace_entry()]) :: t()
  def failure(error, visited_nodes, trace) do
    %__MODULE__{
      status: :failed,
      final_output: nil,
      visited_nodes: visited_nodes,
      trace: trace,
      error: error
    }
  end

  @doc """
  Creates an error workflow result.

  ## Examples

      iex> result = AgentCore.WorkflowEngine.WorkflowResult.error(
      ...>   %{exception: "Invalid workflow spec"},
      ...>   [],
      ...>   []
      ...> )
      iex> result.status
      :error
  """
  @spec error(term(), [atom()], [trace_entry()]) :: t()
  def error(error, visited_nodes \\ [], trace \\ []) do
    %__MODULE__{
      status: :error,
      final_output: nil,
      visited_nodes: visited_nodes,
      trace: trace,
      error: error
    }
  end
end
