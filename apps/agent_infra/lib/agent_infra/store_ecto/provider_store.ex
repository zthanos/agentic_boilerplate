defmodule AgentInfra.StoreEcto.ProviderStore do
  @moduledoc """
  Ecto implementation of the ProviderStore behavior.

  This module implements the AgentCore.Stores.ProviderStore behavior using Ecto
  and PostgreSQL for persistence. It handles conversion between domain structs
  and database schemas.

  Note: This is a placeholder implementation as there are no provider schemas
  in the current database. This would need to be implemented when provider
  persistence is added to the system.
  """

  @behaviour AgentCore.Stores.ProviderStore

  alias AgentCore.{Providers, Stores.ProviderStore}

  # For now, we'll use an in-memory store since there are no provider schemas
  # This should be replaced with proper Ecto implementation when schemas are added

  @impl ProviderStore
  def create(%Providers{} = _provider) do
    {:error, :not_implemented}
  end

  @impl ProviderStore
  def get(_provider_id) do
    {:error, :not_implemented}
  end

  @impl ProviderStore
  def get_by_type(_type) do
    {:error, :not_implemented}
  end

  @impl ProviderStore
  def update(_provider_id, _updates) do
    {:error, :not_implemented}
  end

  @impl ProviderStore
  def delete(_provider_id) do
    {:error, :not_implemented}
  end

  @impl ProviderStore
  def list(_opts \\ []) do
    {:error, :not_implemented}
  end

  @impl ProviderStore
  def list_enabled do
    {:error, :not_implemented}
  end

  @impl ProviderStore
  def list_supporting_model(_model) do
    {:error, :not_implemented}
  end

  @impl ProviderStore
  def count(_opts \\ []) do
    {:error, :not_implemented}
  end

  @impl ProviderStore
  def type_available?(_type, _exclude_id \\ nil) do
    {:error, :not_implemented}
  end

  @impl ProviderStore
  def set_enabled(_provider_id, _enabled) do
    {:error, :not_implemented}
  end

  @impl ProviderStore
  def health_check(_provider_id) do
    {:error, :not_implemented}
  end
end
