defmodule AgentCore.Stores.ProviderStore do
  @moduledoc """
  Behavior for storing and retrieving LLM providers.

  This defines the contract that infrastructure implementations must follow
  for persisting provider configuration data. The behavior is provider-agnostic
  and focuses on domain operations.
  """

  alias AgentCore.Providers

  @type provider_id :: String.t() | integer()
  @type error :: term()
  @type query_opts :: keyword()

  @doc """
  Creates a new provider in the store.

  ## Parameters

  - `provider` - The provider domain object to store

  ## Returns

  - `{:ok, provider_id}` - Provider created successfully with the given ID
  - `{:error, reason}` - Creation failed
  """
  @callback create(Providers.t()) :: {:ok, provider_id()} | {:error, error()}

  @doc """
  Retrieves a provider by its ID.

  ## Parameters

  - `provider_id` - The unique identifier of the provider

  ## Returns

  - `{:ok, provider}` - Provider found and returned
  - `{:error, :not_found}` - Provider does not exist
  - `{:error, reason}` - Retrieval failed
  """
  @callback get(provider_id()) :: {:ok, Providers.t()} | {:error, :not_found} | {:error, error()}

  @doc """
  Retrieves a provider by its type.

  ## Parameters

  - `type` - The provider type (atom)

  ## Returns

  - `{:ok, provider}` - Provider found and returned
  - `{:error, :not_found}` - Provider does not exist
  - `{:error, reason}` - Retrieval failed
  """
  @callback get_by_type(atom()) :: {:ok, Providers.t()} | {:error, :not_found} | {:error, error()}

  @doc """
  Updates an existing provider.

  ## Parameters

  - `provider_id` - The unique identifier of the provider
  - `updates` - Map of fields to update

  ## Returns

  - `{:ok, updated_provider}` - Provider updated successfully
  - `{:error, :not_found}` - Provider does not exist
  - `{:error, reason}` - Update failed
  """
  @callback update(provider_id(), map()) ::
              {:ok, Providers.t()} | {:error, :not_found} | {:error, error()}

  @doc """
  Deletes a provider from the store.

  ## Parameters

  - `provider_id` - The unique identifier of the provider

  ## Returns

  - `:ok` - Provider deleted successfully
  - `{:error, :not_found}` - Provider does not exist
  - `{:error, reason}` - Deletion failed
  """
  @callback delete(provider_id()) :: :ok | {:error, :not_found} | {:error, error()}

  @doc """
  Lists providers based on query criteria.

  ## Parameters

  - `opts` - Query options such as:
    - `:enabled` - Filter by enabled status (true/false)
    - `:type` - Filter by provider type
    - `:limit` - Maximum number of results
    - `:offset` - Number of results to skip
    - `:order_by` - Field to order by (default: type asc)

  ## Returns

  - `{:ok, providers}` - List of matching providers
  - `{:error, reason}` - Query failed
  """
  @callback list(query_opts()) :: {:ok, [Providers.t()]} | {:error, error()}

  @doc """
  Lists all enabled providers.

  ## Returns

  - `{:ok, providers}` - List of enabled providers
  - `{:error, reason}` - Query failed
  """
  @callback list_enabled() :: {:ok, [Providers.t()]} | {:error, error()}

  @doc """
  Lists providers that support a specific model.

  ## Parameters

  - `model` - The model name to check support for

  ## Returns

  - `{:ok, providers}` - List of providers supporting the model
  - `{:error, reason}` - Query failed
  """
  @callback list_supporting_model(String.t()) :: {:ok, [Providers.t()]} | {:error, error()}

  @doc """
  Counts providers matching the given criteria.

  ## Parameters

  - `opts` - Query options (same as list/1)

  ## Returns

  - `{:ok, count}` - Number of matching providers
  - `{:error, reason}` - Count failed
  """
  @callback count(query_opts()) :: {:ok, non_neg_integer()} | {:error, error()}

  @doc """
  Checks if a provider type is available (not taken).

  ## Parameters

  - `type` - The provider type to check
  - `exclude_id` - Optional provider ID to exclude from check (for updates)

  ## Returns

  - `{:ok, true}` - Type is available
  - `{:ok, false}` - Type is taken
  - `{:error, reason}` - Check failed
  """
  @callback type_available?(atom(), provider_id() | nil) :: {:ok, boolean()} | {:error, error()}

  @doc """
  Enables or disables a provider.

  ## Parameters

  - `provider_id` - The unique identifier of the provider
  - `enabled` - Whether to enable (true) or disable (false) the provider

  ## Returns

  - `{:ok, updated_provider}` - Provider status updated
  - `{:error, :not_found}` - Provider does not exist
  - `{:error, reason}` - Update failed
  """
  @callback set_enabled(provider_id(), boolean()) ::
              {:ok, Providers.t()} | {:error, :not_found} | {:error, error()}

  @doc """
  Tests connectivity to a provider.

  ## Parameters

  - `provider_id` - The unique identifier of the provider

  ## Returns

  - `{:ok, :healthy}` - Provider is reachable and healthy
  - `{:ok, :unhealthy}` - Provider is reachable but unhealthy
  - `{:error, :unreachable}` - Provider is not reachable
  - `{:error, :not_found}` - Provider does not exist
  - `{:error, reason}` - Health check failed
  """
  @callback health_check(provider_id()) ::
              {:ok, :healthy | :unhealthy} | {:error, :unreachable | :not_found | error()}
end
