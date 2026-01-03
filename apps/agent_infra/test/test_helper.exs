ExUnit.start()

# Start the Ecto repository for testing
Ecto.Adapters.SQL.Sandbox.mode(AgentInfra.Repo, :manual)
