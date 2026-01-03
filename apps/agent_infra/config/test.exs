import Config

# Configure the database for testing
config :agent_infra, AgentInfra.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 15432,
  database: "agent_infra_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2
