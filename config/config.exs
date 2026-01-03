# This file is responsible for configuring your umbrella
# and **all applications** and their dependencies with the
# help of the Config module.
#
# Note that all applications in your umbrella share the
# same configuration and dependencies, which is why they
# all use the same configuration file. If you want different
# configurations or dependencies per app, it is best to
# move said applications out of the umbrella.
# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# -----------------------------------------------------------------------------
# Agent Infra (Database) Configuration
# -----------------------------------------------------------------------------
config :agent_infra, AgentInfra.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 15432,
  database: "agent_infra_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :agent_infra, ecto_repos: [AgentInfra.Repo]

# -----------------------------------------------------------------------------
# Agent Core: LLM store configurations
# -----------------------------------------------------------------------------

config :agent_core, AgentCore.Llm.Profiles, store: AgentInfra.StoreEcto.LLMProfileStore
config :agent_core, AgentCore.Llm.Agents, store: AgentInfra.StoreEcto.AgentStore
config :agent_core, AgentCore.Llm.Runs, store: AgentInfra.StoreEcto.RunStore

# -----------------------------------------------------------------------------
# Agent Runtime: Store behavior implementations configuration
# -----------------------------------------------------------------------------

config :agent_runtime,
  run_store_impl: AgentInfra.StoreEcto.RunStore,
  profile_store_impl: AgentInfra.StoreEcto.ProfileStore,
  provider_store_impl: AgentInfra.StoreEcto.ProviderStore,
  workflow_store_impl: AgentInfra.StoreEcto.WorkflowStore,
  conversation_store_impl: AgentInfra.StoreEcto.ConversationStore,
  memory_chunk_store_impl: AgentInfra.StoreEcto.MemoryChunkStore

# config/config.exs
config :mime, :types, %{
  "text/event-stream" => ["event-stream"]
}

# -----------------------------------------------------------------------------
# Runtime defaults (can be overridden per env)
# -----------------------------------------------------------------------------

config :agent_runtime, AgentRuntime.Llm.ProviderConfig,
  openai_compatible: [
    base_url: "http://localhost:1234/v1",
    timeout_ms: 60_000,
    connect_timeout_ms: 10_000
  ]

# -----------------------------------------------------------------------------
# Agent Runtime: App startup order and dependencies
# -----------------------------------------------------------------------------

config :agent_runtime,
  # Ensure agent_infra starts before agent_runtime
  included_applications: [:agent_infra]

# -----------------------------------------------------------------------------
# Agent Web: Runtime API configuration
# -----------------------------------------------------------------------------

config :agent_web,
  # Configure agent_web to use only agent_runtime APIs
  agent_runtime_module: AgentRuntime.Agent,
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :agent_web, AgentWebWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: AgentWebWeb.ErrorHTML, json: AgentWebWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: AgentWeb.PubSub,
  live_view: [signing_salt: "GWcv3jaA"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  agent_web: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../apps/agent_web/assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  agent_web: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("../apps/agent_web", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

# Sample configuration:
#
#     config :logger, :default_handler,
#       level: :info
#
#     config :logger, :default_formatter,
#       format: "$date $time [$level] $metadata$message\n",
#       metadata: [:user_id]
#
