import Config

# -----------------------------------------------------------------------------
# agent_web Repo (Postgres)
# -----------------------------------------------------------------------------
config :agent_web, AgentWeb.Repo,
  url: System.get_env("DATABASE_URL") || "ecto://postgres:postgres@localhost:5432/agent_web_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 5

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
# agent_core LLM wiring (tests)
# -----------------------------------------------------------------------------
config :agent_core, AgentCore.Llm.Runs,
  store: AgentCore.Llm.RunStore.Ecto

config :agent_core, AgentCore.Llm.ProviderRouter,
  openai: AgentCore.Llm.Providers.FakeProvider
