defmodule AgentWeb.Repo do
  use Ecto.Repo,
    otp_app: :agent_web,
    adapter: Ecto.Adapters.SQLite3
end
