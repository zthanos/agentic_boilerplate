defmodule AgentWeb.Repo.Migrations.AddAgentRefToLlmRuns do
  use Ecto.Migration

  def change do
    alter table(:llm_runs) do
      add :agent_id, :string
      add :agent_version, :integer
    end

    create index(:llm_runs, [:agent_id, :agent_version])
  end
end
