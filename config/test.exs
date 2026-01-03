# config/test.exs
import Config

# -----------------------------------------------------------------------------
# Agent Infra (Database) Configuration for Testing
# -----------------------------------------------------------------------------
config :agent_infra, AgentInfra.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 15432,
  database: "agent_infra_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# -----------------------------------------------------------------------------
# agent_web Endpoint (no server in test)
# -----------------------------------------------------------------------------
config :agent_web, AgentWebWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "4SmGr7RJ0wnRhN8uNQ4CY6Sq+pjlrRitl2iNUXqExxGNSUSm4whVk0dI3xU0RYzY",
  server: false

# -----------------------------------------------------------------------------
# Logging / Phoenix
# -----------------------------------------------------------------------------
config :logger, level: :warning
config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# -----------------------------------------------------------------------------
# Agent Runtime: Store behavior implementations for testing
# -----------------------------------------------------------------------------

config :agent_runtime,
  run_store_impl: AgentInfra.StoreEcto.RunStore,
  profile_store_impl: AgentInfra.StoreEcto.ProfileStore,
  provider_store_impl: AgentInfra.StoreEcto.ProviderStore,
  workflow_store_impl: AgentInfra.StoreEcto.WorkflowStore,
  conversation_store_impl: AgentInfra.StoreEcto.ConversationStore,
  memory_chunk_store_impl: AgentInfra.StoreEcto.MemoryChunkStore

config :agent_runtime, AgentRuntime.Llm.ProviderConfig,
  openai_compatible: [
    base_url: "http://localhost:1234/v1",
    api_key: "",
    timeout_ms: 60_000,
    connect_timeout_ms: 10_000
  ]

config :agent_runtime, AgentRuntime.Llm.ModelResolver,
  openai_compatible: %{
    local: "openai/gpt-oss-20b",
    gpt4mini: "gpt-4o-mini"
  }
