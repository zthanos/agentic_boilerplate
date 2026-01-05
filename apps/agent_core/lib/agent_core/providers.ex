defmodule AgentCore.Providers do
  @moduledoc """
  Domain module for Service Providers.

  A Provider represents the configuration and metadata for connecting to an AI service provider.
  This module contains the pure domain logic for providers, including validation,
  configuration management, authentication, rate limiting, and health monitoring.
  """

  @enforce_keys [:name, :type]
  defstruct [
    :id,
    :name,
    :type,
    :description,
    # Endpoint configuration
    :base_url,
    :api_version,
    :request_timeout_ms,
    :connection_timeout_ms,
    :read_timeout_ms,
    :retries,
    :retry_backoff_ms,
    :default_headers,
    :custom_params,
    # Authentication
    :auth_type,
    :api_key,
    :oauth2_config,
    :custom_auth_headers,
    :token_refresh_url,
    :credentials_encrypted,
    # Rate limiting
    :requests_per_minute,
    :requests_per_hour,
    :concurrent_connections,
    :daily_quota,
    :monthly_quota,
    :burst_limit,
    # Cost configuration
    :input_token_cost_per_1k,
    :output_token_cost_per_1k,
    :request_cost,
    :monthly_subscription,
    :currency,
    :billing_model,
    # Health status
    :health_status,
    :last_check_at,
    :response_time_ms,
    :error_rate,
    :uptime_percentage,
    :last_error,
    :consecutive_failures,
    # Metadata
    :tags,
    :supported_models,
    :inserted_at,
    :updated_at,
    # Default values
    enabled: true
  ]

  @type provider_type :: atom()  # Registry-based provider types (e.g., :openai_compatible, :fake, :anthropic)
  @type auth_type :: :api_key | :oauth2 | :custom_header | :none
  @type billing_model :: :token_based | :request_based | :subscription
  @type health_status :: :online | :offline | :degraded | :unknown
  @type model_list :: [String.t()]

  @type t :: %__MODULE__{
          id: String.t() | integer() | nil,
          name: String.t(),
          enabled: boolean(),
          type: provider_type(),
          description: String.t() | nil,
          # Endpoint configuration
          base_url: String.t() | nil,
          api_version: String.t() | nil,
          request_timeout_ms: integer() | nil,
          connection_timeout_ms: integer() | nil,
          read_timeout_ms: integer() | nil,
          retries: integer() | nil,
          retry_backoff_ms: integer() | nil,
          default_headers: map() | nil,
          custom_params: map() | nil,
          # Authentication
          auth_type: auth_type() | nil,
          api_key: String.t() | nil,
          oauth2_config: map() | nil,
          custom_auth_headers: map() | nil,
          token_refresh_url: String.t() | nil,
          credentials_encrypted: boolean() | nil,
          # Rate limiting
          requests_per_minute: integer() | nil,
          requests_per_hour: integer() | nil,
          concurrent_connections: integer() | nil,
          daily_quota: integer() | nil,
          monthly_quota: integer() | nil,
          burst_limit: integer() | nil,
          # Cost configuration
          input_token_cost_per_1k: float() | nil,
          output_token_cost_per_1k: float() | nil,
          request_cost: float() | nil,
          monthly_subscription: float() | nil,
          currency: String.t() | nil,
          billing_model: billing_model() | nil,
          # Health status
          health_status: health_status() | nil,
          last_check_at: DateTime.t() | NaiveDateTime.t() | nil,
          response_time_ms: integer() | nil,
          error_rate: float() | nil,
          uptime_percentage: float() | nil,
          last_error: String.t() | nil,
          consecutive_failures: integer() | nil,
          # Metadata
          tags: [atom()] | nil,
          supported_models: model_list() | nil,
          inserted_at: DateTime.t() | NaiveDateTime.t() | nil,
          updated_at: DateTime.t() | NaiveDateTime.t() | nil
        }

  @doc """
  Creates a new provider with the given attributes.

  ## Examples

      iex> AgentCore.Providers.new(%{
      ...>   name: "OpenAI Provider",
      ...>   type: :cloud,
      ...>   base_url: "https://api.openai.com/v1"
      ...> })
      {:ok, %AgentCore.Providers{...}}
  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    required_fields = [:name, :type]

    case validate_required_fields(attrs, required_fields) do
      :ok ->
        attrs_with_defaults =
          attrs
          |> Map.put_new(:enabled, true)
          |> Map.put_new(:request_timeout_ms, 60_000)
          |> Map.put_new(:connection_timeout_ms, 30_000)
          |> Map.put_new(:read_timeout_ms, 30_000)
          |> Map.put_new(:retries, 3)
          |> Map.put_new(:retry_backoff_ms, 1_000)
          |> Map.put_new(:auth_type, :none)
          |> Map.put_new(:currency, "EUR")
          |> Map.put_new(:billing_model, :token_based)
          |> Map.put_new(:health_status, :unknown)
          |> Map.put_new(:consecutive_failures, 0)
          |> Map.put_new(:credentials_encrypted, false)
          |> Map.put_new(:tags, [])

        case validate_provider_attrs(attrs_with_defaults) do
          :ok ->
            provider = struct(__MODULE__, attrs_with_defaults)
            {:ok, provider}

          {:error, _} = error ->
            error
        end

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Validates a provider's attributes.
  """
  @spec validate(t()) :: :ok | {:error, term()}
  def validate(%__MODULE__{} = provider) do
    provider
    |> Map.from_struct()
    |> validate_provider_attrs()
  end

  @doc """
  Checks if a provider is enabled and can be used.
  """
  @spec enabled?(t()) :: boolean()
  def enabled?(%__MODULE__{enabled: enabled}), do: enabled == true

  @doc """
  Checks if a provider has valid authentication configured.
  """
  @spec has_authentication?(t()) :: boolean()
  def has_authentication?(%__MODULE__{auth_type: :none}), do: false
  def has_authentication?(%__MODULE__{auth_type: :api_key, api_key: nil}), do: false

  def has_authentication?(%__MODULE__{auth_type: :api_key, api_key: key}) when is_binary(key),
    do: true

  def has_authentication?(%__MODULE__{auth_type: :oauth2, oauth2_config: nil}), do: false

  def has_authentication?(%__MODULE__{auth_type: :oauth2, oauth2_config: config})
      when is_map(config), do: true

  def has_authentication?(%__MODULE__{auth_type: :custom_header, custom_auth_headers: nil}),
    do: false

  def has_authentication?(%__MODULE__{auth_type: :custom_header, custom_auth_headers: headers})
      when is_map(headers), do: true

  def has_authentication?(_), do: false

  @doc """
  Gets the current health status of a provider.
  """
  @spec health_status(t()) :: health_status()
  def health_status(%__MODULE__{health_status: nil}), do: :unknown
  def health_status(%__MODULE__{health_status: status}), do: status

  @doc """
  Checks if a provider is healthy (online status).
  """
  @spec healthy?(t()) :: boolean()
  def healthy?(%__MODULE__{health_status: :online}), do: true
  def healthy?(_), do: false

  @doc """
  Gets the effective cost configuration for a provider.
  """
  @spec cost_config(t()) :: %{
          input_cost: float() | nil,
          output_cost: float() | nil,
          request_cost: float() | nil,
          subscription: float() | nil,
          currency: String.t(),
          billing_model: billing_model()
        }
  def cost_config(%__MODULE__{} = provider) do
    %{
      input_cost: provider.input_token_cost_per_1k,
      output_cost: provider.output_token_cost_per_1k,
      request_cost: provider.request_cost,
      subscription: provider.monthly_subscription,
      currency: provider.currency || "EUR",
      billing_model: provider.billing_model || :token_based
    }
  end

  @doc """
  Gets the rate limiting configuration for a provider.
  """
  @spec rate_limits(t()) :: %{
          per_minute: integer() | nil,
          per_hour: integer() | nil,
          concurrent: integer() | nil,
          daily: integer() | nil,
          monthly: integer() | nil,
          burst: integer() | nil
        }
  def rate_limits(%__MODULE__{} = provider) do
    %{
      per_minute: provider.requests_per_minute,
      per_hour: provider.requests_per_hour,
      concurrent: provider.concurrent_connections,
      daily: provider.daily_quota,
      monthly: provider.monthly_quota,
      burst: provider.burst_limit
    }
  end

  @doc """
  Gets the effective request timeout for a provider.
  """
  @spec request_timeout(t()) :: integer()
  def request_timeout(%__MODULE__{request_timeout_ms: nil}), do: 30_000
  def request_timeout(%__MODULE__{request_timeout_ms: timeout}), do: timeout

  @doc """
  Gets the retry configuration for a provider.
  """
  @spec retry_config(t()) :: %{retries: integer(), backoff_ms: integer()}
  def retry_config(%__MODULE__{} = provider) do
    %{
      retries: provider.retries || 3,
      backoff_ms: provider.retry_backoff_ms || 1_000
    }
  end

  @doc """
  Checks if a provider supports the given model.
  """
  @spec supports_model?(t(), String.t()) :: boolean()
  def supports_model?(%__MODULE__{supported_models: nil}, _model), do: true

  def supports_model?(%__MODULE__{supported_models: models}, model) when is_list(models) do
    Enum.member?(models, model)
  end

  @doc """
  Builds request headers for a provider, including authentication.
  """
  @spec request_headers(t()) :: map()
  def request_headers(%__MODULE__{} = provider) do
    base_headers = provider.default_headers || %{}

    case provider.auth_type do
      :api_key ->
        case provider.api_key do
          nil -> base_headers
          key -> Map.put(base_headers, "Authorization", "Bearer #{key}")
        end

      :custom_header ->
        case provider.custom_auth_headers do
          nil -> base_headers
          headers -> Map.merge(base_headers, headers)
        end

      _ ->
        base_headers
    end
  end

  @doc """
  Updates a provider with new attributes.
  """
  @spec update(t(), map()) :: {:ok, t()} | {:error, term()}
  def update(%__MODULE__{} = provider, attrs) when is_map(attrs) do
    updated_attrs =
      provider
      |> Map.from_struct()
      |> Map.merge(attrs)
      |> Map.put(:updated_at, DateTime.utc_now())

    case validate_provider_attrs(updated_attrs) do
      :ok ->
        updated_provider = struct(__MODULE__, updated_attrs)
        {:ok, updated_provider}

      {:error, _} = error ->
        error
    end
  end

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

  defp validate_provider_attrs(attrs) do
    with :ok <- validate_name(attrs[:name]),
         :ok <- validate_type(attrs[:type]),
         :ok <- validate_base_url(attrs[:base_url]),
         :ok <- validate_timeout(attrs[:request_timeout_ms]),
         :ok <- validate_timeout(attrs[:connection_timeout_ms]),
         :ok <- validate_timeout(attrs[:read_timeout_ms]),
         :ok <- validate_retries(attrs[:retries]),
         :ok <- validate_backoff(attrs[:retry_backoff_ms]),
         :ok <- validate_headers(attrs[:default_headers]),
         :ok <- validate_auth_type(attrs[:auth_type]),
         :ok <- validate_billing_model(attrs[:billing_model]),
         :ok <- validate_health_status(attrs[:health_status]),
         :ok <- validate_models(attrs[:supported_models]) do
      :ok
    end
  end

  defp validate_name(name) when is_binary(name) and byte_size(name) > 0, do: :ok
  defp validate_name(_), do: {:error, :invalid_name}

  defp validate_type(type) when is_atom(type) do
    case AgentRuntime.Providers.Registry.get_provider(type) do
      {:ok, _module} -> :ok
      {:error, :not_found} -> {:error, :invalid_type}
    end
  end

  defp validate_type(_), do: {:error, :invalid_type}

  defp validate_base_url(nil), do: :ok

  defp validate_base_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme} when scheme in ["http", "https"] -> :ok
      _ -> {:error, :invalid_base_url}
    end
  end

  defp validate_base_url(_), do: {:error, :invalid_base_url}

  defp validate_auth_type(nil), do: :ok
  defp validate_auth_type(type) when type in [:api_key, :oauth2, :custom_header, :none], do: :ok
  defp validate_auth_type(_), do: {:error, :invalid_auth_type}

  defp validate_billing_model(nil), do: :ok

  defp validate_billing_model(model) when model in [:token_based, :request_based, :subscription],
    do: :ok

  defp validate_billing_model(_), do: {:error, :invalid_billing_model}

  defp validate_health_status(nil), do: :ok

  defp validate_health_status(status) when status in [:online, :offline, :degraded, :unknown],
    do: :ok

  defp validate_health_status(_), do: {:error, :invalid_health_status}

  defp validate_timeout(nil), do: :ok
  defp validate_timeout(timeout) when is_integer(timeout) and timeout > 0, do: :ok
  defp validate_timeout(_), do: {:error, :invalid_timeout}

  defp validate_retries(nil), do: :ok
  defp validate_retries(retries) when is_integer(retries) and retries >= 0, do: :ok
  defp validate_retries(_), do: {:error, :invalid_retries}

  defp validate_backoff(nil), do: :ok
  defp validate_backoff(backoff) when is_integer(backoff) and backoff >= 0, do: :ok
  defp validate_backoff(_), do: {:error, :invalid_backoff}

  defp validate_headers(nil), do: :ok
  defp validate_headers(headers) when is_map(headers), do: :ok
  defp validate_headers(_), do: {:error, :invalid_headers}

  defp validate_models(nil), do: :ok

  defp validate_models(models) when is_list(models) do
    if Enum.all?(models, &is_binary/1) do
      :ok
    else
      {:error, :invalid_models}
    end
  end

  defp validate_models(_), do: {:error, :invalid_models}
end
