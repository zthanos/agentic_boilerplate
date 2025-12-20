defmodule AgentCore.Repo do
  use Ecto.Repo,
    otp_app: :agent_core,
    adapter: Ecto.Adapters.SQLite3
end
