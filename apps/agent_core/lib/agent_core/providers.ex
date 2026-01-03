defmodule AgentCore.Providers do
  @moduledoc """
  Domain module for LLM Providers.

  A Provider represents the configuration and metadata for connecting to an LLM service.
  This module contains the pure domain logic for providers, including validation
  and configuration management.
  """

  @enforce_keys [:type, :base_url]
  defstruct [
    :type,
    :base_url,
    :api_key,
    :default_headers,
    :request_timeout_ms,
    :retries,
    :retry_backoff_ms,
    :enabled,
    :name,
    :description,
    :supported_models,
    :created_at,
    :updated_at
  ]

  @type provider_type :: :openai | :azure_openai | :anthropic | :google | :local | atom()
  @type model_list :: [String.t()]

  @type t :: %__MODULE__{
          type: provider_type(),
          base_url: String.t(),
          api_key: String.t() | nil,
          default_headers: map() | nil,
          request_timeout_ms: integer() | nil,
          retries: integer() | nil,
          retry_backoff_ms: integer() | nil,
          enabled: boolean() | nil,
          name: String.t() | nil,
          description: String.t() | nil,
          supported_models: model_list() | nil,
          created_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @doc """
  Creates a new provider with the given attributes.

  ## Examples

      iex> AgentCore.Providers.new(%{
      ...>   type: :openai,
      ...>   base_url: "https://api.openai.com/v1"
      ...> })
      {:ok, %AgentCore.Providers{...}}
  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    required_fields = [:type, :base_url]

    case validate_required_fields(attrs, required_fields) do
      :ok ->
        attrs_with_defaults =
          attrs
          |> Map.put_new(:enabled, true)
          |> Map.put_new(:request_timeout_ms, 30_000)
          |> Map.put_new(:retries, 3)
          |> Map.put_new(:retry_backoff_ms, 1_000)

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
  Checks if a provider supports the given model.
  """
  @spec supports_model?(t(), String.t()) :: boolean()
  def supports_model?(%__MODULE__{supported_models: nil}, _model), do: true

  def supports_model?(%__MODULE__{supported_models: models}, model) when is_list(models) do
    Enum.member?(models, model)
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
  Builds request headers for a provider, including authentication.
  """
  @spec request_headers(t()) :: map()
  def request_headers(%__MODULE__{} = provider) do
    base_headers = provider.default_headers || %{}

    case provider.api_key do
      nil -> base_headers
      key -> Map.put(base_headers, "Authorization", "Bearer #{key}")
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
    with :ok <- validate_type(attrs[:type]),
         :ok <- validate_base_url(attrs[:base_url]),
         :ok <- validate_timeout(attrs[:request_timeout_ms]),
         :ok <- validate_retries(attrs[:retries]),
         :ok <- validate_backoff(attrs[:retry_backoff_ms]),
         :ok <- validate_headers(attrs[:default_headers]),
         :ok <- validate_models(attrs[:supported_models]) do
      :ok
    end
  end

  defp validate_type(type) when is_atom(type), do: :ok
  defp validate_type(_), do: {:error, :invalid_type}

  defp validate_base_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme} when scheme in ["http", "https"] -> :ok
      _ -> {:error, :invalid_base_url}
    end
  end

  defp validate_base_url(_), do: {:error, :invalid_base_url}

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
