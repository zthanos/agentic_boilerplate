defmodule AgentCore.Stores.ProfileStore do
  @moduledoc """
  Behavior for storing and retrieving LLM profiles.

  This defines the contract that infrastructure implementations must follow
  for persisting profile data. The behavior is provider-agnostic and focuses
  on domain operations.
  """

  alias AgentCore.Profiles

  @type profile_id :: String.t() | integer()
  @type error :: term()
  @type query_opts :: keyword()

  @doc """
  Creates a new profile in the store.

  ## Parameters

  - `profile` - The profile domain object to store

  ## Returns

  - `{:ok, profile_id}` - Profile created successfully with the given ID
  - `{:error, reason}` - Creation failed
  """
  @callback create(Profiles.t()) :: {:ok, profile_id()} | {:error, error()}

  @doc """
  Retrieves a profile by its ID.

  ## Parameters

  - `profile_id` - The unique identifier of the profile

  ## Returns

  - `{:ok, profile}` - Profile found and returned
  - `{:error, :not_found}` - Profile does not exist
  - `{:error, reason}` - Retrieval failed
  """
  @callback get(profile_id()) :: {:ok, Profiles.t()} | {:error, :not_found} | {:error, error()}

  @doc """
  Retrieves a profile by its name.

  ## Parameters

  - `name` - The name of the profile

  ## Returns

  - `{:ok, profile}` - Profile found and returned
  - `{:error, :not_found}` - Profile does not exist
  - `{:error, reason}` - Retrieval failed
  """
  @callback get_by_name(String.t()) ::
              {:ok, Profiles.t()} | {:error, :not_found} | {:error, error()}

  @doc """
  Updates an existing profile.

  ## Parameters

  - `profile_id` - The unique identifier of the profile
  - `updates` - Map of fields to update

  ## Returns

  - `{:ok, updated_profile}` - Profile updated successfully
  - `{:error, :not_found}` - Profile does not exist
  - `{:error, reason}` - Update failed
  """
  @callback update(profile_id(), map()) ::
              {:ok, Profiles.t()} | {:error, :not_found} | {:error, error()}

  @doc """
  Deletes a profile from the store.

  ## Parameters

  - `profile_id` - The unique identifier of the profile

  ## Returns

  - `:ok` - Profile deleted successfully
  - `{:error, :not_found}` - Profile does not exist
  - `{:error, reason}` - Deletion failed
  """
  @callback delete(profile_id()) :: :ok | {:error, :not_found} | {:error, error()}

  @doc """
  Lists profiles based on query criteria.

  ## Parameters

  - `opts` - Query options such as:
    - `:enabled` - Filter by enabled status (true/false)
    - `:provider` - Filter by provider type
    - `:tags` - Filter by tags (list of strings)
    - `:limit` - Maximum number of results
    - `:offset` - Number of results to skip
    - `:order_by` - Field to order by (default: name asc)

  ## Returns

  - `{:ok, profiles}` - List of matching profiles
  - `{:error, reason}` - Query failed
  """
  @callback list(query_opts()) :: {:ok, [Profiles.t()]} | {:error, error()}

  @doc """
  Lists all enabled profiles.

  ## Returns

  - `{:ok, profiles}` - List of enabled profiles
  - `{:error, reason}` - Query failed
  """
  @callback list_enabled() :: {:ok, [Profiles.t()]} | {:error, error()}

  @doc """
  Lists profiles by provider type.

  ## Parameters

  - `provider` - The provider type (atom)

  ## Returns

  - `{:ok, profiles}` - List of profiles for the provider
  - `{:error, reason}` - Query failed
  """
  @callback list_by_provider(atom()) :: {:ok, [Profiles.t()]} | {:error, error()}

  @doc """
  Counts profiles matching the given criteria.

  ## Parameters

  - `opts` - Query options (same as list/1)

  ## Returns

  - `{:ok, count}` - Number of matching profiles
  - `{:error, reason}` - Count failed
  """
  @callback count(query_opts()) :: {:ok, non_neg_integer()} | {:error, error()}

  @doc """
  Checks if a profile name is available (not taken).

  ## Parameters

  - `name` - The profile name to check
  - `exclude_id` - Optional profile ID to exclude from check (for updates)

  ## Returns

  - `{:ok, true}` - Name is available
  - `{:ok, false}` - Name is taken
  - `{:error, reason}` - Check failed
  """
  @callback name_available?(String.t(), profile_id() | nil) ::
              {:ok, boolean()} | {:error, error()}

  @doc """
  Enables or disables a profile.

  ## Parameters

  - `profile_id` - The unique identifier of the profile
  - `enabled` - Whether to enable (true) or disable (false) the profile

  ## Returns

  - `{:ok, updated_profile}` - Profile status updated
  - `{:error, :not_found}` - Profile does not exist
  - `{:error, reason}` - Update failed
  """
  @callback set_enabled(profile_id(), boolean()) ::
              {:ok, Profiles.t()} | {:error, :not_found} | {:error, error()}

  @doc """
  Searches profiles by name or description.

  ## Parameters

  - `query` - Search query string
  - `opts` - Additional query options

  ## Returns

  - `{:ok, profiles}` - List of matching profiles
  - `{:error, reason}` - Search failed
  """
  @callback search(String.t(), query_opts()) :: {:ok, [Profiles.t()]} | {:error, error()}
end
