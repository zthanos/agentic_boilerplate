defmodule AgentWeb.Repo.Migrations.LlmAgents do
  use Ecto.Migration

  def change do
    create table(:llm_agents, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :agent_id, :string, null: false
      add :version, :integer, null: false
      add :status, :string, null: false, default: "active"
      add :checksum, :string
      add :definition, :map, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:llm_agents, [:agent_id, :version])
    create index(:llm_agents, [:status])
  end
end
