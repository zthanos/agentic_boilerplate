import Config

# Configure the database for production
# You should configure the database URL via environment variables
# For example: DATABASE_URL=ecto://USER:PASS@HOST/DATABASE
config :agent_infra, AgentInfra.Repo,
  # ssl: true,
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")
