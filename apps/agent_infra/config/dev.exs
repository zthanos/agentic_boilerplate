import Config

# Configure the database for development
config :agent_infra, AgentInfra.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "agent_infra_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10
