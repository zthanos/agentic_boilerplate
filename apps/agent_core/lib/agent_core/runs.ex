defmodule AgentCore.Runs do
  @moduledoc """
  Domain module for LLM Runs.

  A Run represents a single execution of an LLM request with a specific configuration.
  This module contains the pure domain logic for runs, including state transitions
  and business rules.
  """

  alias __MODULE__

  @enforce_keys [:id, :trace_id, :fingerprint, :profile_id, :status]
  defstruct [
    :id,
    :trace_id,
    :parent_run_id,
    :phase,
    :fingerprint,
    :profile_id,
    :profile_name,
    :provider,
    :model,
    :policy_version,
    :status,
    :resolved_at,
    :started_at,
    :finished_at,
    :overrides,
    :invocation_config,
    :outcome,
    :error_reason,
    :created_at,
    :updated_at
  ]

  @type id :: String.t()
  @type trace_id :: String.t()
  @type status :: :pending | :running | :completed | :failed
  @type outcome :: map()

  @type t :: %__MODULE__{
          id: id(),
          trace_id: trace_id(),
          parent_run_id: id() | nil,
          phase: String.t() | nil,
          fingerprint: String.t(),
          profile_id: String.t() | integer(),
          profile_name: String.t() | nil,
          provider: atom() | String.t(),
          model: String.t() | atom(),
          policy_version: String.t() | nil,
          status: status(),
          resolved_at: DateTime.t() | nil,
          started_at: DateTime.t() | nil,
          finished_at: DateTime.t() | nil,
          overrides: map() | nil,
          invocation_config: map() | nil,
          outcome: outcome() | nil,
          error_reason: term() | nil,
          created_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @doc """
  Creates a new run with the given attributes.

  ## Examples

      iex> AgentCore.Runs.new(%{
      ...>   id: "run-123",
      ...>   trace_id: "trace-456",
      ...>   fingerprint: "fp-789",
      ...>   profile_id: "profile-1"
      ...> })
      {:ok, %AgentCore.Runs{status: :pending, ...}}
  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    required_fields = [:id, :trace_id, :fingerprint, :profile_id]

    case validate_required_fields(attrs, required_fields) do
      :ok ->
        run = struct(__MODULE__, Map.put(attrs, :status, :pending))
        {:ok, run}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Validates that a run can transition to the given status.

  Valid transitions:
  - :pending -> :running
  - :running -> :completed
  - :running -> :failed
  - Any status -> :failed (for error cases)
  """
  @spec can_transition?(t(), status()) :: boolean()
  def can_transition?(%Runs{status: :pending}, :running), do: true
  def can_transition?(%Runs{status: :running}, :completed), do: true
  def can_transition?(%Runs{status: :running}, :failed), do: true
  # Can always fail
  def can_transition?(%Runs{}, :failed), do: true
  def can_transition?(_, _), do: false

  @doc """
  Transitions a run to the given status if the transition is valid.
  """
  @spec transition(t(), status(), map()) :: {:ok, t()} | {:error, :invalid_transition}
  def transition(%Runs{} = run, new_status, attrs \\ %{}) do
    if can_transition?(run, new_status) do
      updated_run =
        run
        |> Map.merge(attrs)
        |> Map.put(:status, new_status)
        |> Map.put(:updated_at, DateTime.utc_now())
        |> maybe_set_timestamp(new_status)

      {:ok, updated_run}
    else
      {:error, :invalid_transition}
    end
  end

  @doc """
  Marks a run as started.
  """
  @spec mark_started(t()) :: {:ok, t()} | {:error, :invalid_transition}
  def mark_started(%Runs{} = run) do
    transition(run, :running, %{started_at: DateTime.utc_now()})
  end

  @doc """
  Marks a run as completed with the given outcome.
  """
  @spec mark_completed(t(), outcome()) :: {:ok, t()} | {:error, :invalid_transition}
  def mark_completed(%Runs{} = run, outcome) when is_map(outcome) do
    transition(run, :completed, %{
      outcome: outcome,
      finished_at: DateTime.utc_now()
    })
  end

  @doc """
  Marks a run as failed with the given reason and optional outcome.
  """
  @spec mark_failed(t(), term(), outcome()) :: {:ok, t()} | {:error, :invalid_transition}
  def mark_failed(%Runs{} = run, reason, outcome \\ %{}) when is_map(outcome) do
    transition(run, :failed, %{
      error_reason: reason,
      outcome: outcome,
      finished_at: DateTime.utc_now()
    })
  end

  @doc """
  Checks if a run is in a terminal state (completed or failed).
  """
  @spec terminal?(t()) :: boolean()
  def terminal?(%Runs{status: status}) when status in [:completed, :failed], do: true
  def terminal?(_), do: false

  @doc """
  Checks if a run is currently active (running).
  """
  @spec active?(t()) :: boolean()
  def active?(%Runs{status: :running}), do: true
  def active?(_), do: false

  # Private helpers

  defp validate_required_fields(attrs, required_fields) do
    missing_fields =
      required_fields
      |> Enum.reject(&Map.has_key?(attrs, &1))

    case missing_fields do
      [] -> :ok
      fields -> {:error, {:missing_required_fields, fields}}
    end
  end

  defp maybe_set_timestamp(run, :running) do
    Map.put(run, :started_at, DateTime.utc_now())
  end

  defp maybe_set_timestamp(run, status) when status in [:completed, :failed] do
    Map.put(run, :finished_at, DateTime.utc_now())
  end

  defp maybe_set_timestamp(run, _), do: run
end
