defmodule AgentCore.WorkflowEngine.Context do
  @moduledoc """
  Runtime context structure for workflow execution.

  The Context provides a consistent structure for sharing state and tracking
  execution across workflow steps. It maintains proper data separation with
  different maps for different types of information.

  ## Structure

  - `decisions` - Routing decisions made during execution
  - `artifacts` - Step outputs and payloads
  - `debug` - Execution trace and debugging information
  - `meta` - Run metadata like run_id, trace_id, and budget
  - `events` - Optional event stream for advanced use cases

  ## Usage

      # Create a new context
      ctx = AgentCore.WorkflowEngine.Context.new()

      # Add routing decision
      ctx = put_in(ctx.decisions[:needs_processing], true)

      # Store step output
      ctx = put_in(ctx.artifacts[:processed_data], result)

      # Add debug information
      ctx = put_in(ctx.debug[:step_duration], 150)

  ## Data Organization

  Each map serves a specific purpose:

  - **decisions**: Boolean or enum values used for workflow routing
  - **artifacts**: Rich data structures produced by steps
  - **debug**: Execution traces, timing, and diagnostic information
  - **meta**: Workflow metadata like IDs, budgets, and configuration
  - **events**: Optional event log for complex workflows
  """

  defstruct [
    # %{atom() => term()} - routing decisions
    :decisions,
    # %{atom() => term()} - step outputs and payloads
    :artifacts,
    # %{atom() => term()} - execution trace data
    :debug,
    # %{atom() => term()} - run metadata
    :meta,
    # [map()] - optional event stream
    :events
  ]

  @type t :: %__MODULE__{
          decisions: %{atom() => term()},
          artifacts: %{atom() => term()},
          debug: %{atom() => term()},
          meta: %{atom() => term()},
          events: [map()]
        }

  @doc """
  Creates a new workflow context with empty maps.

  ## Examples

      iex> ctx = AgentCore.WorkflowEngine.Context.new()
      iex> ctx.decisions
      %{}
      iex> ctx.artifacts
      %{}
  """
  @spec new() :: t()
  def new do
    %__MODULE__{
      decisions: %{},
      artifacts: %{},
      debug: %{},
      meta: %{},
      events: []
    }
  end

  @doc """
  Creates a new workflow context with initial metadata.

  ## Examples

      iex> ctx = AgentCore.WorkflowEngine.Context.new(%{run_id: "123", trace_id: "abc"})
      iex> ctx.meta[:run_id]
      "123"
  """
  @spec new(map()) :: t()
  def new(initial_meta) when is_map(initial_meta) do
    %__MODULE__{
      decisions: %{},
      artifacts: %{},
      debug: %{},
      meta: initial_meta,
      events: []
    }
  end

  @doc """
  Adds a routing decision to the context.

  ## Examples

      iex> ctx = AgentCore.WorkflowEngine.Context.new()
      iex> ctx = AgentCore.WorkflowEngine.Context.put_decision(ctx, :needs_history, true)
      iex> ctx.decisions[:needs_history]
      true
  """
  @spec put_decision(t(), atom(), term()) :: t()
  def put_decision(%__MODULE__{} = ctx, key, value) when is_atom(key) do
    put_in(ctx.decisions[key], value)
  end

  @doc """
  Adds an artifact to the context.

  ## Examples

      iex> ctx = AgentCore.WorkflowEngine.Context.new()
      iex> ctx = AgentCore.WorkflowEngine.Context.put_artifact(ctx, :result, %{data: "processed"})
      iex> ctx.artifacts[:result]
      %{data: "processed"}
  """
  @spec put_artifact(t(), atom(), term()) :: t()
  def put_artifact(%__MODULE__{} = ctx, key, value) when is_atom(key) do
    put_in(ctx.artifacts[key], value)
  end

  @doc """
  Adds debug information to the context.

  ## Examples

      iex> ctx = AgentCore.WorkflowEngine.Context.new()
      iex> ctx = AgentCore.WorkflowEngine.Context.put_debug(ctx, :step_duration, 150)
      iex> ctx.debug[:step_duration]
      150
  """
  @spec put_debug(t(), atom(), term()) :: t()
  def put_debug(%__MODULE__{} = ctx, key, value) when is_atom(key) do
    put_in(ctx.debug[key], value)
  end

  @doc """
  Adds an event to the context event stream.

  ## Examples

      iex> ctx = AgentCore.WorkflowEngine.Context.new()
      iex> ctx = AgentCore.WorkflowEngine.Context.add_event(ctx, %{type: :step_started, node: :process})
      iex> length(ctx.events)
      1
  """
  @spec add_event(t(), map()) :: t()
  def add_event(%__MODULE__{} = ctx, event) when is_map(event) do
    %{ctx | events: [event | ctx.events]}
  end

  @doc """
  Gets a decision value from the context.

  ## Examples

      iex> ctx = AgentCore.WorkflowEngine.Context.new()
      iex> ctx = AgentCore.WorkflowEngine.Context.put_decision(ctx, :needs_history, true)
      iex> AgentCore.WorkflowEngine.Context.get_decision(ctx, :needs_history)
      true
      iex> AgentCore.WorkflowEngine.Context.get_decision(ctx, :missing)
      nil
  """
  @spec get_decision(t(), atom()) :: term()
  def get_decision(%__MODULE__{} = ctx, key) when is_atom(key) do
    ctx.decisions[key]
  end

  @doc """
  Gets an artifact value from the context.

  ## Examples

      iex> ctx = AgentCore.WorkflowEngine.Context.new()
      iex> ctx = AgentCore.WorkflowEngine.Context.put_artifact(ctx, :result, "data")
      iex> AgentCore.WorkflowEngine.Context.get_artifact(ctx, :result)
      "data"
      iex> AgentCore.WorkflowEngine.Context.get_artifact(ctx, :missing)
      nil
  """
  @spec get_artifact(t(), atom()) :: term()
  def get_artifact(%__MODULE__{} = ctx, key) when is_atom(key) do
    ctx.artifacts[key]
  end
end
