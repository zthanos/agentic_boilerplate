defmodule AgentCore.Stores.RunStore do
  @moduledoc """
  Behavior for storing and retrieving LLM runs.

  This defines the contract that infrastructure implementations must follow
  for persisting run data. The behavior is provider-agnostic and focuses
  on domain operations.
  """

  alias AgentCore.Runs

  @type run_id :: String.t()
  @type trace_id :: String.t()
  @type error :: term()
  @type outcome :: map()
  @type query_opts :: keyword()

  @doc """
  Creates a new run in the store.

  ## Parameters

  - `run` - The run domain object to store

  ## Returns

  - `{:ok, run_id}` - Run created successfully with the given ID
  - `{:error, reason}` - Creation failed
  """
  @callback create(Runs.t()) :: {:ok, run_id()} | {:error, error()}

  @doc """
  Retrieves a run by its ID.

  ## Parameters

  - `run_id` - The unique identifier of the run

  ## Returns

  - `{:ok, run}` - Run found and returned
  - `{:error, :not_found}` - Run does not exist
  - `{:error, reason}` - Retrieval failed
  """
  @callback get(run_id()) :: {:ok, Runs.t()} | {:error, :not_found} | {:error, error()}

  @doc """
  Updates an existing run.

  ## Parameters

  - `run_id` - The unique identifier of the run
  - `updates` - Map of fields to update

  ## Returns

  - `{:ok, updated_run}` - Run updated successfully
  - `{:error, :not_found}` - Run does not exist
  - `{:error, reason}` - Update failed
  """
  @callback update(run_id(), map()) :: {:ok, Runs.t()} | {:error, :not_found} | {:error, error()}

  @doc """
  Deletes a run from the store.

  ## Parameters

  - `run_id` - The unique identifier of the run

  ## Returns

  - `:ok` - Run deleted successfully
  - `{:error, :not_found}` - Run does not exist
  - `{:error, reason}` - Deletion failed
  """
  @callback delete(run_id()) :: :ok | {:error, :not_found} | {:error, error()}

  @doc """
  Lists runs based on query criteria.

  ## Parameters

  - `opts` - Query options such as:
    - `:trace_id` - Filter by trace ID
    - `:profile_id` - Filter by profile ID
    - `:status` - Filter by run status
    - `:fingerprint` - Filter by configuration fingerprint
    - `:limit` - Maximum number of results
    - `:offset` - Number of results to skip
    - `:order_by` - Field to order by (default: created_at desc)

  ## Returns

  - `{:ok, runs}` - List of matching runs
  - `{:error, reason}` - Query failed
  """
  @callback list(query_opts()) :: {:ok, [Runs.t()]} | {:error, error()}

  @doc """
  Marks a run as started.

  ## Parameters

  - `run_id` - The unique identifier of the run

  ## Returns

  - `{:ok, run_id}` - Run marked as started
  - `{:error, :not_found}` - Run does not exist
  - `{:error, reason}` - Update failed
  """
  @callback mark_started(run_id()) :: {:ok, run_id()} | {:error, :not_found} | {:error, error()}

  @doc """
  Marks a run as completed with outcome.

  ## Parameters

  - `run_id` - The unique identifier of the run
  - `outcome` - The completion outcome data

  ## Returns

  - `{:ok, run_id}` - Run marked as completed
  - `{:error, :not_found}` - Run does not exist
  - `{:error, reason}` - Update failed
  """
  @callback mark_completed(run_id(), outcome()) ::
              {:ok, run_id()} | {:error, :not_found} | {:error, error()}

  @doc """
  Marks a run as failed with error and outcome.

  ## Parameters

  - `run_id` - The unique identifier of the run
  - `error_reason` - The reason for failure
  - `outcome` - Any partial outcome data

  ## Returns

  - `{:ok, run_id}` - Run marked as failed
  - `{:error, :not_found}` - Run does not exist
  - `{:error, reason}` - Update failed
  """
  @callback mark_failed(run_id(), error(), outcome()) ::
              {:ok, run_id()} | {:error, :not_found} | {:error, error()}

  @doc """
  Counts runs matching the given criteria.

  ## Parameters

  - `opts` - Query options (same as list/1)

  ## Returns

  - `{:ok, count}` - Number of matching runs
  - `{:error, reason}` - Count failed
  """
  @callback count(query_opts()) :: {:ok, non_neg_integer()} | {:error, error()}

  @doc """
  Gets the latest run for a given fingerprint.

  ## Parameters

  - `fingerprint` - The configuration fingerprint

  ## Returns

  - `{:ok, run}` - Latest run found
  - `{:error, :not_found}` - No runs with that fingerprint
  - `{:error, reason}` - Query failed
  """
  @callback latest_by_fingerprint(String.t()) ::
              {:ok, Runs.t()} | {:error, :not_found} | {:error, error()}

  @doc """
  Lists runs for a specific trace ID.

  ## Parameters

  - `trace_id` - The trace identifier
  - `opts` - Additional query options

  ## Returns

  - `{:ok, runs}` - List of runs in the trace
  - `{:error, reason}` - Query failed
  """
  @callback list_by_trace(trace_id(), query_opts()) :: {:ok, [Runs.t()]} | {:error, error()}
end
