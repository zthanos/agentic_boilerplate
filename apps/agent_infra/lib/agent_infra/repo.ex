defmodule AgentInfra.Repo do
  use Ecto.Repo,
    otp_app: :agent_infra,
    adapter: Ecto.Adapters.Postgres
end
