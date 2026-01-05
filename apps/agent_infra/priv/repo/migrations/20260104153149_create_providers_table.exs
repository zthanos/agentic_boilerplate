defmodule AgentInfra.Repo.Migrations.CreateProvidersTable do
  use Ecto.Migration

  def change do
    create table(:providers, primary_key: false) do
      add :id, :string, primary_key: true
      add :name, :string, null: false
      add :enabled, :boolean, null: false, default: true
      add :type, :string, null: false
      add :description, :string

      # Endpoint configuration
      add :base_url, :string
      add :api_version, :string
      add :request_timeout_ms, :integer
      add :connection_timeout_ms, :integer
      add :read_timeout_ms, :integer
      add :retries, :integer
      add :retry_backoff_ms, :integer
      add :default_headers, :map
      add :custom_params, :map

      # Authentication
      add :auth_type, :string
      add :api_key, :string
      add :oauth2_config, :map
      add :custom_auth_headers, :map
      add :token_refresh_url, :string
      add :credentials_encrypted, :boolean

      # Rate limiting
      add :requests_per_minute, :integer
      add :requests_per_hour, :integer
      add :concurrent_connections, :integer
      add :daily_quota, :integer
      add :monthly_quota, :integer
      add :burst_limit, :integer

      # Cost configuration
      add :input_token_cost_per_1k, :float
      add :output_token_cost_per_1k, :float
      add :request_cost, :float
      add :monthly_subscription, :float
      add :currency, :string
      add :billing_model, :string

      # Health status
      add :health_status, :string
      add :last_check_at, :utc_datetime
      add :response_time_ms, :integer
      add :error_rate, :float
      add :uptime_percentage, :float
      add :last_error, :string
      add :consecutive_failures, :integer

      # Metadata
      add :tags, {:array, :string}, default: []
      add :supported_models, {:array, :string}, default: []

      timestamps()
    end

    create unique_index(:providers, [:name])
    create index(:providers, [:enabled])
    create index(:providers, [:type])
    create index(:providers, [:health_status])
  end
end
