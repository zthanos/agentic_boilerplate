import Config

# Configure the database
config :agent_infra, AgentInfra.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 15432,
  database: "agent_infra_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

# Configure Ecto repositories
config :agent_infra, ecto_repos: [AgentInfra.Repo]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
