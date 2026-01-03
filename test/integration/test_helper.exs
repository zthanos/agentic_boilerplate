# Integration test helper
ExUnit.start()

# Start the applications needed for integration testing
Application.ensure_all_started(:agent_infra)
Application.ensure_all_started(:agent_runtime)
Application.ensure_all_started(:agent_web)

# Configure Ecto sandbox for concurrent testing
Ecto.Adapters.SQL.Sandbox.mode(AgentInfra.Repo, :manual)
