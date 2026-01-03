defmodule AgentRuntime.Stores.ProfileStore do
  @moduledoc """
  Runtime wrapper for profile store behavior.

  This module delegates to the configured profile store implementation,
  providing a consistent interface for the runtime layer while
  allowing the actual implementation to be configured.
  """

  @behaviour AgentCore.Stores.ProfileStore

  alias AgentCore.Profiles

  @impl true
  def create(%Profiles{} = profile) do
    store_impl().create(profile)
  end

  @impl true
  def get(profile_id) do
    store_impl().get(profile_id)
  end

  @impl true
  def get_by_name(name) do
    store_impl().get_by_name(name)
  end

  @impl true
  def update(profile_id, updates) do
    store_impl().update(profile_id, updates)
  end

  @impl true
  def delete(profile_id) do
    store_impl().delete(profile_id)
  end

  @impl true
  def list(opts \\ []) do
    store_impl().list(opts)
  end

  @impl true
  def list_enabled do
    store_impl().list_enabled()
  end

  @impl true
  def list_by_provider(provider) do
    store_impl().list_by_provider(provider)
  end

  @impl true
  def count(opts \\ []) do
    store_impl().count(opts)
  end

  @impl true
  def name_available?(name, exclude_id \\ nil) do
    store_impl().name_available?(name, exclude_id)
  end

  @impl true
  def set_enabled(profile_id, enabled) do
    store_impl().set_enabled(profile_id, enabled)
  end

  @impl true
  def search(query, opts \\ []) do
    store_impl().search(query, opts)
  end

  # Private helper to get configured implementation
  defp store_impl do
    Application.get_env(:agent_runtime, :profile_store_impl, AgentInfra.StoreEcto.ProfileStore)
  end
end
