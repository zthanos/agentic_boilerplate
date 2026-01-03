defmodule AgentCore.Stores.WorkflowStore do
  @moduledoc """
  Behavior for storing and retrieving workflow specifications.

  This defines the contract that infrastructure implementations must follow
  for persisting workflow specification data. The behavior is provider-agnostic
  and focuses on domain operations.
  """

  alias AgentCore.Workflows.Spec

  @type workflow_id :: atom()
  @type version :: integer()
  @type error :: term()
  @type query_opts :: keyword()

  @doc """
  Stores a workflow specification.

  ## Parameters

  - `spec` - The workflow specification to store

  ## Returns

  - `{:ok, {workflow_id, version}}` - Spec stored successfully
  - `{:error, reason}` - Storage failed
  """
  @callback put(Spec.t()) :: {:ok, {workflow_id(), version()}} | {:error, error()}

  @doc """
  Retrieves a workflow specification by ID and version.

  ## Parameters

  - `workflow_id` - The workflow identifier
  - `version` - The specific version (optional, defaults to latest)

  ## Returns

  - `{:ok, spec}` - Specification found and returned
  - `{:error, :not_found}` - Specification does not exist
  - `{:error, reason}` - Retrieval failed
  """
  @callback get(workflow_id(), version() | nil) ::
              {:ok, Spec.t()} | {:error, :not_found} | {:error, error()}

  @doc """
  Retrieves the latest version of a workflow specification.

  ## Parameters

  - `workflow_id` - The workflow identifier

  ## Returns

  - `{:ok, spec}` - Latest specification found and returned
  - `{:error, :not_found}` - Workflow does not exist
  - `{:error, reason}` - Retrieval failed
  """
  @callback get_latest(workflow_id()) ::
              {:ok, Spec.t()} | {:error, :not_found} | {:error, error()}

  @doc """
  Deletes a specific version of a workflow specification.

  ## Parameters

  - `workflow_id` - The workflow identifier
  - `version` - The specific version to delete

  ## Returns

  - `:ok` - Specification deleted successfully
  - `{:error, :not_found}` - Specification does not exist
  - `{:error, reason}` - Deletion failed
  """
  @callback delete(workflow_id(), version()) :: :ok | {:error, :not_found} | {:error, error()}

  @doc """
  Deletes all versions of a workflow.

  ## Parameters

  - `workflow_id` - The workflow identifier

  ## Returns

  - `:ok` - All versions deleted successfully
  - `{:error, :not_found}` - Workflow does not exist
  - `{:error, reason}` - Deletion failed
  """
  @callback delete_all_versions(workflow_id()) :: :ok | {:error, :not_found} | {:error, error()}

  @doc """
  Lists all workflow IDs.

  ## Returns

  - `{:ok, workflow_ids}` - List of all workflow identifiers
  - `{:error, reason}` - Listing failed
  """
  @callback list_workflows() :: {:ok, [workflow_id()]} | {:error, error()}

  @doc """
  Lists all versions of a specific workflow.

  ## Parameters

  - `workflow_id` - The workflow identifier

  ## Returns

  - `{:ok, versions}` - List of version numbers (sorted desc)
  - `{:error, :not_found}` - Workflow does not exist
  - `{:error, reason}` - Listing failed
  """
  @callback list_versions(workflow_id()) ::
              {:ok, [version()]} | {:error, :not_found} | {:error, error()}

  @doc """
  Lists workflow specifications based on query criteria.

  ## Parameters

  - `opts` - Query options such as:
    - `:latest_only` - Only return latest versions (default: false)
    - `:limit` - Maximum number of results
    - `:offset` - Number of results to skip
    - `:order_by` - Field to order by (default: id asc, version desc)

  ## Returns

  - `{:ok, specs}` - List of matching specifications
  - `{:error, reason}` - Query failed
  """
  @callback list(query_opts()) :: {:ok, [Spec.t()]} | {:error, error()}

  @doc """
  Counts workflow specifications matching the given criteria.

  ## Parameters

  - `opts` - Query options (same as list/1)

  ## Returns

  - `{:ok, count}` - Number of matching specifications
  - `{:error, reason}` - Count failed
  """
  @callback count(query_opts()) :: {:ok, non_neg_integer()} | {:error, error()}

  @doc """
  Checks if a workflow exists.

  ## Parameters

  - `workflow_id` - The workflow identifier
  - `version` - Optional specific version to check

  ## Returns

  - `{:ok, true}` - Workflow exists
  - `{:ok, false}` - Workflow does not exist
  - `{:error, reason}` - Check failed
  """
  @callback exists?(workflow_id(), version() | nil) :: {:ok, boolean()} | {:error, error()}

  @doc """
  Gets the next version number for a workflow.

  ## Parameters

  - `workflow_id` - The workflow identifier

  ## Returns

  - `{:ok, next_version}` - Next available version number
  - `{:error, reason}` - Version calculation failed
  """
  @callback next_version(workflow_id()) :: {:ok, version()} | {:error, error()}

  @doc """
  Validates and stores a workflow specification.

  This combines validation with storage in a single operation.

  ## Parameters

  - `spec` - The workflow specification to validate and store

  ## Returns

  - `{:ok, {workflow_id, version}}` - Spec validated and stored successfully
  - `{:error, {:validation_failed, errors}}` - Validation failed
  - `{:error, reason}` - Storage failed
  """
  @callback validate_and_put(Spec.t()) ::
              {:ok, {workflow_id(), version()}}
              | {:error, {:validation_failed, [atom()]} | error()}
end
