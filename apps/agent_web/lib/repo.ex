defmodule AgentWeb.Repo do
  use Ecto.Repo,
    otp_app: :agent_web,
    adapter: Ecto.Adapters.Postgres
end
