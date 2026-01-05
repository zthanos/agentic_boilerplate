defmodule AgentInfra.StoreEcto.ProviderStoreTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias AgentCore.Providers
  alias AgentInfra.StoreEcto.ProviderStore
  alias AgentInfra.Repo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    # Clean up any existing providers to avoid unique constraint violations
    Repo.delete_all(AgentInfra.Schema.Provider)
    :ok
  end

  # Property 1: Provider Creation and Persistence
  # Feature: service-provider-management, Property 1: For any valid provider data submitted through the form, the system should create a proper ServiceProvider struct and successfully persist it to the database
  property "provider creation and persistence" do
    check all(provider_attrs <- valid_provider_generator()) do
      # Create provider using domain logic
      {:ok, provider} = Providers.new(provider_attrs)

      # Store provider using ProviderStore
      assert {:ok, provider_id} = ProviderStore.create(provider)
      assert is_binary(provider_id)

      # Verify persistence by retrieving the provider
      assert {:ok, retrieved_provider} = ProviderStore.get(provider_id)

      # Verify core fields match
      assert retrieved_provider.name == provider.name
      assert retrieved_provider.type == provider.type
      assert retrieved_provider.enabled == provider.enabled
      assert retrieved_provider.description == provider.description

      # Verify endpoint configuration
      assert retrieved_provider.base_url == provider.base_url
      assert retrieved_provider.api_version == provider.api_version
      assert retrieved_provider.request_timeout_ms == provider.request_timeout_ms

      # Verify authentication fields
      assert retrieved_provider.auth_type == provider.auth_type
      assert retrieved_provider.api_key == provider.api_key

      # Verify rate limiting fields
      assert retrieved_provider.requests_per_minute == provider.requests_per_minute
      assert retrieved_provider.requests_per_hour == provider.requests_per_hour

      # Verify cost configuration
      assert retrieved_provider.input_token_cost_per_1k == provider.input_token_cost_per_1k
      assert retrieved_provider.output_token_cost_per_1k == provider.output_token_cost_per_1k

      # Verify metadata
      assert retrieved_provider.tags == provider.tags
      assert retrieved_provider.supported_models == provider.supported_models

      # Verify timestamps are set
      assert retrieved_provider.inserted_at != nil
      assert retrieved_provider.updated_at != nil
    end
  end

  # Generator for valid provider attributes
  defp valid_provider_generator do
    gen all(
          name <- unique_name_generator(),
          type <- member_of([:cloud, :local, :enterprise, :custom]),
          enabled <- boolean(),
          description <- one_of([constant(nil), string(:alphanumeric, max_length: 200)]),
          base_url <- one_of([constant(nil), url_generator()]),
          api_version <- one_of([constant(nil), string(:alphanumeric, max_length: 10)]),
          request_timeout_ms <- one_of([constant(nil), integer(1000..120_000)]),
          connection_timeout_ms <- one_of([constant(nil), integer(1000..60_000)]),
          read_timeout_ms <- one_of([constant(nil), integer(1000..60_000)]),
          retries <- one_of([constant(nil), integer(0..10)]),
          retry_backoff_ms <- one_of([constant(nil), integer(100..10_000)]),
          auth_type <-
            one_of([constant(nil), member_of([:api_key, :oauth2, :custom_header, :none])]),
          api_key <-
            one_of([constant(nil), string(:alphanumeric, min_length: 10, max_length: 100)]),
          requests_per_minute <- one_of([constant(nil), integer(1..10_000)]),
          requests_per_hour <- one_of([constant(nil), integer(1..100_000)]),
          concurrent_connections <- one_of([constant(nil), integer(1..100)]),
          daily_quota <- one_of([constant(nil), integer(1..1_000_000)]),
          monthly_quota <- one_of([constant(nil), integer(1..10_000_000)]),
          input_token_cost <- one_of([constant(nil), float(min: 0.0, max: 1.0)]),
          output_token_cost <- one_of([constant(nil), float(min: 0.0, max: 1.0)]),
          request_cost <- one_of([constant(nil), float(min: 0.0, max: 10.0)]),
          monthly_subscription <- one_of([constant(nil), float(min: 0.0, max: 1000.0)]),
          currency <- one_of([constant(nil), member_of(["USD", "EUR", "GBP"])]),
          billing_model <-
            one_of([constant(nil), member_of([:token_based, :request_based, :subscription])]),
          health_status <-
            one_of([constant(nil), member_of([:online, :offline, :degraded, :unknown])]),
          tags <- one_of([constant(nil), list_of(atom(:alphanumeric), max_length: 5)]),
          supported_models <-
            one_of([
              constant(nil),
              list_of(string(:alphanumeric, max_length: 20), max_length: 10)
            ])
        ) do
      %{
        name: name,
        type: type,
        enabled: enabled,
        description: description,
        base_url: base_url,
        api_version: api_version,
        request_timeout_ms: request_timeout_ms,
        connection_timeout_ms: connection_timeout_ms,
        read_timeout_ms: read_timeout_ms,
        retries: retries,
        retry_backoff_ms: retry_backoff_ms,
        auth_type: auth_type,
        api_key: api_key,
        requests_per_minute: requests_per_minute,
        requests_per_hour: requests_per_hour,
        concurrent_connections: concurrent_connections,
        daily_quota: daily_quota,
        monthly_quota: monthly_quota,
        input_token_cost_per_1k: input_token_cost,
        output_token_cost_per_1k: output_token_cost,
        request_cost: request_cost,
        monthly_subscription: monthly_subscription,
        currency: currency,
        billing_model: billing_model,
        health_status: health_status,
        tags: tags,
        supported_models: supported_models
      }
    end
  end

  # Generator for unique provider names
  defp unique_name_generator do
    gen all(
          base_name <- string(:alphanumeric, min_length: 1, max_length: 20),
          uuid <- binary(length: 16)
        ) do
      encoded_uuid = Base.url_encode64(uuid, padding: false)
      "#{base_name}_#{encoded_uuid}"
    end
  end

  # Generator for valid URLs
  defp url_generator do
    gen all(
          scheme <- member_of(["http", "https"]),
          domain <- string(:alphanumeric, min_length: 3, max_length: 20),
          tld <- member_of(["com", "org", "net", "io"]),
          path <- one_of([constant(""), string(:alphanumeric, max_length: 20)])
        ) do
      base_url = "#{scheme}://#{domain}.#{tld}"
      if path == "", do: base_url, else: "#{base_url}/#{path}"
    end
  end
end
