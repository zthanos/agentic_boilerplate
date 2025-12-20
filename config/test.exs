import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :agent_web, AgentWeb.Repo,
  database: Path.expand("../agent_web_test.db", __DIR__),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :agent_web, AgentWebWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "4SmGr7RJ0wnRhN8uNQ4CY6Sq+pjlrRitl2iNUXqExxGNSUSm4whVk0dI3xU0RYzY",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

config :agent_core, AgentCore.Repo,
  database: "data/agent_core_test.sqlite3",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 5

config :agent_core, AgentCore.Llm.Runs,
  store: AgentCore.Llm.RunStore.Ecto
