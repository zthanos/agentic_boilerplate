# apps/agent_runtime/config/test.exs
import Config

# Logger configuration for test environment
config :logger, level: :warning

# Database configuration for test environment (if needed)
# config :agent_runtime, AgentRuntime.Repo,
#   pool: Ecto.Adapters.SQL.Sandbox,
#   pool_size: 5

# ExUnit configuration
ExUnit.start()

config :agent_runtime, :run_store, AgentRuntime.Llm.RunStore.Memory
