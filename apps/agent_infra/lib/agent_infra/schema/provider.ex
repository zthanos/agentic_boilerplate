defmodule AgentInfra.Schema.Provider do
  @moduledoc """
  Ecto schema for provider configurations.

  This schema stores provider configuration data for the existing AgentCore.Providers domain model.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  schema "providers" do
    field(:name, :string)
    field(:enabled, :boolean, default: true)
    field(:type, :string)
    field(:description, :string)

    # Endpoint configuration
    field(:base_url, :string)
    field(:api_version, :string)
    field(:request_timeout_ms, :integer)
    field(:connection_timeout_ms, :integer)
    field(:read_timeout_ms, :integer)
    field(:retries, :integer)
    field(:retry_backoff_ms, :integer)
    field(:default_headers, :map)
    field(:custom_params, :map)

    # Authentication
    field(:auth_type, :string)
    field(:api_key, :string)
    field(:oauth2_config, :map)
    field(:custom_auth_headers, :map)
    field(:token_refresh_url, :string)
    field(:credentials_encrypted, :boolean)

    # Rate limiting
    field(:requests_per_minute, :integer)
    field(:requests_per_hour, :integer)
    field(:concurrent_connections, :integer)
    field(:daily_quota, :integer)
    field(:monthly_quota, :integer)
    field(:burst_limit, :integer)

    # Cost configuration
    field(:input_token_cost_per_1k, :float)
    field(:output_token_cost_per_1k, :float)
    field(:request_cost, :float)
    field(:monthly_subscription, :float)
    field(:currency, :string)
    field(:billing_model, :string)

    # Health status
    field(:health_status, :string)
    field(:last_check_at, :utc_datetime)
    field(:response_time_ms, :integer)
    field(:error_rate, :float)
    field(:uptime_percentage, :float)
    field(:last_error, :string)
    field(:consecutive_failures, :integer)

    # Metadata
    field(:tags, {:array, :string}, default: [])
    field(:supported_models, {:array, :string}, default: [])

    timestamps()
  end

  @doc false
  def changeset(provider, attrs) do
    provider
    |> cast(attrs, [
      :id,
      :name,
      :enabled,
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
      :supported_models
    ])
    |> validate_required([:name, :type])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_provider_type()
    |> validate_inclusion(:auth_type, ["api_key", "oauth2", "custom_header", "none"])
    |> validate_inclusion(:billing_model, ["token_based", "request_based", "subscription"])
    |> validate_inclusion(:health_status, ["online", "offline", "degraded", "unknown"])
    |> validate_base_url()
    |> unique_constraint(:name)
  end

  defp validate_base_url(changeset) do
    case get_field(changeset, :base_url) do
      nil ->
        changeset

      url when is_binary(url) ->
        case URI.parse(url) do
          %URI{scheme: scheme} when scheme in ["http", "https"] -> changeset
          _ -> add_error(changeset, :base_url, "must be a valid HTTP or HTTPS URL")
        end

      _ ->
        add_error(changeset, :base_url, "must be a valid URL string")
    end
  end

  defp validate_provider_type(changeset) do
    case get_field(changeset, :type) do
      nil ->
        changeset

      type when is_binary(type) ->
        # Convert string to atom for registry lookup
        try do
          type_atom = String.to_existing_atom(type)
          validate_provider_type_in_registry(changeset, type_atom)
        rescue
          ArgumentError ->
            # If atom doesn't exist, try to create it and validate
            type_atom = String.to_atom(type)
            validate_provider_type_in_registry(changeset, type_atom)
        end

      type when is_atom(type) ->
        validate_provider_type_in_registry(changeset, type)

      _ ->
        add_error(changeset, :type, "must be a valid provider type")
    end
  end

  defp validate_provider_type_in_registry(changeset, type_atom) do
    case AgentRuntime.Providers.Registry.get_provider(type_atom) do
      {:ok, _module} ->
        changeset

      {:error, :not_found} ->
        # Get available types for better error message
        case AgentRuntime.Providers.Registry.list_providers() do
          {:ok, providers} ->
            available_types =
              providers
              |> Enum.map(fn {name, _module} -> to_string(name) end)
              |> Enum.join(", ")

            add_error(changeset, :type, "is not a registered provider type. Available types: #{available_types}")

          {:error, _} ->
            add_error(changeset, :type, "is not a registered provider type")
        end
    end
  end
end
