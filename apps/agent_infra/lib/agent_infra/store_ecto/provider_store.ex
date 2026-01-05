defmodule AgentInfra.StoreEcto.ProviderStore do
  @moduledoc """
  Ecto implementation of the ProviderStore behavior.

  This module implements the AgentCore.Stores.ProviderStore behavior using Ecto
  and the Provider schema for persistence. It handles conversion between
  AgentCore.Providers domain structs and database schemas.
  """

  @behaviour AgentCore.Stores.ProviderStore

  alias AgentCore.{Providers, Stores.ProviderStore}
  alias AgentInfra.{Repo, Schema.Provider}
  import Ecto.Query

  @impl ProviderStore
  def create(%Providers{} = provider) do
    attrs = provider_to_schema_attrs(provider)

    %Provider{}
    |> Provider.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, schema} -> {:ok, schema.id}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @impl ProviderStore
  def get(provider_id) do
    case Repo.get(Provider, to_string(provider_id)) do
      nil -> {:error, :not_found}
      schema -> {:ok, schema_to_provider(schema)}
    end
  end

  @impl ProviderStore
  def get_by_type(type) do
    query = from(p in Provider, where: p.type == ^to_string(type), limit: 1)

    case Repo.one(query) do
      nil -> {:error, :not_found}
      schema -> {:ok, schema_to_provider(schema)}
    end
  end

  @impl ProviderStore
  def update(provider_id, updates) do
    case Repo.get(Provider, to_string(provider_id)) do
      nil ->
        {:error, :not_found}

      schema ->
        schema
        |> Provider.changeset(updates)
        |> Repo.update()
        |> case do
          {:ok, updated_schema} -> {:ok, schema_to_provider(updated_schema)}
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  @impl ProviderStore
  def delete(provider_id) do
    case Repo.get(Provider, to_string(provider_id)) do
      nil ->
        {:error, :not_found}

      schema ->
        case Repo.delete(schema) do
          {:ok, _} -> :ok
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  @impl ProviderStore
  def list(opts \\ []) do
    query = build_list_query(opts)

    try do
      providers =
        query
        |> Repo.all()
        |> Enum.map(&schema_to_provider/1)

      {:ok, providers}
    rescue
      _error -> {:error, :database_error}
    end
  end

  @impl ProviderStore
  def list_enabled do
    list(enabled: true)
  end

  @impl ProviderStore
  def list_supporting_model(model) do
    query = from(p in Provider, where: fragment("? = ANY(?)", ^model, p.supported_models))

    try do
      providers =
        query
        |> Repo.all()
        |> Enum.map(&schema_to_provider/1)

      {:ok, providers}
    rescue
      _error -> {:error, :database_error}
    end
  end

  @impl ProviderStore
  def count(opts \\ []) do
    query = build_list_query(opts)

    try do
      count = Repo.aggregate(query, :count, :id)
      {:ok, count}
    rescue
      _error -> {:error, :database_error}
    end
  end

  @impl ProviderStore
  def type_available?(type, exclude_id \\ nil) do
    query = from(p in Provider, where: p.type == ^to_string(type))

    query =
      if exclude_id do
        from(p in query, where: p.id != ^to_string(exclude_id))
      else
        query
      end

    try do
      case Repo.one(query) do
        nil -> {:ok, true}
        _provider -> {:ok, false}
      end
    rescue
      _error -> {:error, :database_error}
    end
  end

  @impl ProviderStore
  def set_enabled(provider_id, enabled) do
    __MODULE__.update(provider_id, %{enabled: enabled})
  end

  @impl ProviderStore
  def health_check(provider_id) do
    case get(provider_id) do
      {:ok, provider} ->
        case Providers.health_status(provider) do
          :online -> {:ok, :healthy}
          :degraded -> {:ok, :unhealthy}
          _ -> {:error, :unreachable}
        end

      {:error, :not_found} ->
        {:error, :not_found}

      error ->
        error
    end
  end

  # Private helper functions

  defp generate_id do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end

  defp provider_to_schema_attrs(%Providers{} = provider) do
    %{
      id: provider.id || generate_id(),
      name: provider.name,
      enabled: provider.enabled,
      type: to_string(provider.type),
      description: provider.description,
      # Endpoint configuration
      base_url: provider.base_url,
      api_version: provider.api_version,
      request_timeout_ms: provider.request_timeout_ms,
      connection_timeout_ms: provider.connection_timeout_ms,
      read_timeout_ms: provider.read_timeout_ms,
      retries: provider.retries,
      retry_backoff_ms: provider.retry_backoff_ms,
      default_headers: provider.default_headers,
      custom_params: provider.custom_params,
      # Authentication
      auth_type: provider.auth_type && to_string(provider.auth_type),
      api_key: provider.api_key,
      oauth2_config: provider.oauth2_config,
      custom_auth_headers: provider.custom_auth_headers,
      token_refresh_url: provider.token_refresh_url,
      credentials_encrypted: provider.credentials_encrypted,
      # Rate limiting
      requests_per_minute: provider.requests_per_minute,
      requests_per_hour: provider.requests_per_hour,
      concurrent_connections: provider.concurrent_connections,
      daily_quota: provider.daily_quota,
      monthly_quota: provider.monthly_quota,
      burst_limit: provider.burst_limit,
      # Cost configuration
      input_token_cost_per_1k: provider.input_token_cost_per_1k,
      output_token_cost_per_1k: provider.output_token_cost_per_1k,
      request_cost: provider.request_cost,
      monthly_subscription: provider.monthly_subscription,
      currency: provider.currency,
      billing_model: provider.billing_model && to_string(provider.billing_model),
      # Health status
      health_status: provider.health_status && to_string(provider.health_status),
      last_check_at: provider.last_check_at,
      response_time_ms: provider.response_time_ms,
      error_rate: provider.error_rate,
      uptime_percentage: provider.uptime_percentage,
      last_error: provider.last_error,
      consecutive_failures: provider.consecutive_failures,
      # Metadata
      tags: provider.tags && Enum.map(provider.tags, &to_string/1),
      supported_models: provider.supported_models
    }
  end

  defp schema_to_provider(%Provider{} = schema) do
    %Providers{
      id: schema.id,
      name: schema.name,
      enabled: schema.enabled,
      type: schema.type && String.to_existing_atom(schema.type),
      description: schema.description,
      # Endpoint configuration
      base_url: schema.base_url,
      api_version: schema.api_version,
      request_timeout_ms: schema.request_timeout_ms,
      connection_timeout_ms: schema.connection_timeout_ms,
      read_timeout_ms: schema.read_timeout_ms,
      retries: schema.retries,
      retry_backoff_ms: schema.retry_backoff_ms,
      default_headers: schema.default_headers,
      custom_params: schema.custom_params,
      # Authentication
      auth_type: schema.auth_type && String.to_existing_atom(schema.auth_type),
      api_key: schema.api_key,
      oauth2_config: schema.oauth2_config,
      custom_auth_headers: schema.custom_auth_headers,
      token_refresh_url: schema.token_refresh_url,
      credentials_encrypted: schema.credentials_encrypted,
      # Rate limiting
      requests_per_minute: schema.requests_per_minute,
      requests_per_hour: schema.requests_per_hour,
      concurrent_connections: schema.concurrent_connections,
      daily_quota: schema.daily_quota,
      monthly_quota: schema.monthly_quota,
      burst_limit: schema.burst_limit,
      # Cost configuration
      input_token_cost_per_1k: schema.input_token_cost_per_1k,
      output_token_cost_per_1k: schema.output_token_cost_per_1k,
      request_cost: schema.request_cost,
      monthly_subscription: schema.monthly_subscription,
      currency: schema.currency,
      billing_model: schema.billing_model && String.to_existing_atom(schema.billing_model),
      # Health status
      health_status: schema.health_status && String.to_existing_atom(schema.health_status),
      last_check_at: schema.last_check_at,
      response_time_ms: schema.response_time_ms,
      error_rate: schema.error_rate,
      uptime_percentage: schema.uptime_percentage,
      last_error: schema.last_error,
      consecutive_failures: schema.consecutive_failures,
      # Metadata
      tags: schema.tags && Enum.map(schema.tags, &String.to_atom/1),
      supported_models: schema.supported_models,
      inserted_at: schema.inserted_at,
      updated_at: schema.updated_at
    }
  end

  defp build_list_query(opts) do
    base_query = from(p in Provider)

    Enum.reduce(opts, base_query, fn
      {:enabled, enabled}, q ->
        from(p in q, where: p.enabled == ^enabled)

      {:type, type}, q ->
        from(p in q, where: p.type == ^to_string(type))

      {:limit, limit}, q ->
        from(p in q, limit: ^limit)

      {:offset, offset}, q ->
        from(p in q, offset: ^offset)

      _other, q ->
        q
    end)
  end
end
