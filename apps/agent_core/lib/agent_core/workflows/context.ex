defmodule AgentCore.Workflows.Context do
  @moduledoc """
  Workflow execution context.

  The context holds the state and data that flows through a workflow execution.
  It contains artifacts (data), decisions (routing information), and metadata
  about the execution.
  """

  defstruct [
    # Workflow execution data/artifacts
    artifacts: %{},
    # Decision values for routing
    decisions: %{},
    # Execution metadata
    metadata: %{},
    # Execution trace/history
    trace: [],
    # Current execution state
    status: :running,
    # Error information if failed
    error: nil
  ]

  @type artifact_key :: atom() | String.t()
  @type decision_key :: atom() | String.t()
  @type metadata_key :: atom() | String.t()
  @type status :: :running | :completed | :failed

  @type t :: %__MODULE__{
          artifacts: map(),
          decisions: map(),
          metadata: map(),
          trace: [map()],
          status: status(),
          error: term() | nil
        }

  @doc """
  Creates a new workflow context.

  ## Examples

      iex> AgentCore.Workflows.Context.new()
      %AgentCore.Workflows.Context{status: :running, ...}

      iex> AgentCore.Workflows.Context.new(%{input: "data"})
      %AgentCore.Workflows.Context{artifacts: %{input: "data"}, ...}
  """
  @spec new(map()) :: t()
  def new(initial_artifacts \\ %{}) do
    %__MODULE__{
      artifacts: initial_artifacts,
      decisions: %{},
      metadata: %{},
      trace: [],
      status: :running,
      error: nil
    }
  end

  @doc """
  Sets an artifact in the context.
  """
  @spec put_artifact(t(), artifact_key(), term()) :: t()
  def put_artifact(%__MODULE__{} = context, key, value) do
    %{context | artifacts: Map.put(context.artifacts, key, value)}
  end

  @doc """
  Gets an artifact from the context.
  """
  @spec get_artifact(t(), artifact_key(), term()) :: term()
  def get_artifact(%__MODULE__{artifacts: artifacts}, key, default \\ nil) do
    Map.get(artifacts, key, default)
  end

  @doc """
  Checks if an artifact exists in the context.
  """
  @spec has_artifact?(t(), artifact_key()) :: boolean()
  def has_artifact?(%__MODULE__{artifacts: artifacts}, key) do
    Map.has_key?(artifacts, key)
  end

  @doc """
  Sets a decision value in the context.
  """
  @spec put_decision(t(), decision_key(), term()) :: t()
  def put_decision(%__MODULE__{} = context, key, value) do
    %{context | decisions: Map.put(context.decisions, key, value)}
  end

  @doc """
  Gets a decision value from the context.
  """
  @spec get_decision(t(), decision_key(), term()) :: term()
  def get_decision(%__MODULE__{decisions: decisions}, key, default \\ nil) do
    Map.get(decisions, key, default)
  end

  @doc """
  Sets metadata in the context.
  """
  @spec put_metadata(t(), metadata_key(), term()) :: t()
  def put_metadata(%__MODULE__{} = context, key, value) do
    %{context | metadata: Map.put(context.metadata, key, value)}
  end

  @doc """
  Gets metadata from the context.
  """
  @spec get_metadata(t(), metadata_key(), term()) :: term()
  def get_metadata(%__MODULE__{metadata: metadata}, key, default \\ nil) do
    Map.get(metadata, key, default)
  end

  @doc """
  Adds an entry to the execution trace.
  """
  @spec add_trace(t(), map()) :: t()
  def add_trace(%__MODULE__{} = context, entry) when is_map(entry) do
    entry_with_timestamp = Map.put_new(entry, :timestamp, DateTime.utc_now())
    %{context | trace: [entry_with_timestamp | context.trace]}
  end

  @doc """
  Gets the execution trace (most recent first).
  """
  @spec get_trace(t()) :: [map()]
  def get_trace(%__MODULE__{trace: trace}), do: trace

  @doc """
  Marks the context as completed.
  """
  @spec mark_completed(t()) :: t()
  def mark_completed(%__MODULE__{} = context) do
    %{context | status: :completed}
  end

  @doc """
  Marks the context as failed with an error.
  """
  @spec mark_failed(t(), term()) :: t()
  def mark_failed(%__MODULE__{} = context, error) do
    %{context | status: :failed, error: error}
  end

  @doc """
  Checks if the context is in a running state.
  """
  @spec running?(t()) :: boolean()
  def running?(%__MODULE__{status: :running}), do: true
  def running?(_), do: false

  @doc """
  Checks if the context is completed.
  """
  @spec completed?(t()) :: boolean()
  def completed?(%__MODULE__{status: :completed}), do: true
  def completed?(_), do: false

  @doc """
  Checks if the context has failed.
  """
  @spec failed?(t()) :: boolean()
  def failed?(%__MODULE__{status: :failed}), do: true
  def failed?(_), do: false

  @doc """
  Merges artifacts from another context or map.
  """
  @spec merge_artifacts(t(), t() | map()) :: t()
  def merge_artifacts(%__MODULE__{} = context, %__MODULE__{artifacts: other_artifacts}) do
    %{context | artifacts: Map.merge(context.artifacts, other_artifacts)}
  end

  def merge_artifacts(%__MODULE__{} = context, artifacts) when is_map(artifacts) do
    %{context | artifacts: Map.merge(context.artifacts, artifacts)}
  end

  @doc """
  Converts the context to a map for serialization.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = context) do
    Map.from_struct(context)
  end

  @doc """
  Creates a context from a map.
  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    struct(__MODULE__, map)
  end
end
