defmodule AgentCore.Repo.Migrations.CreateLlmRuns do
  use Ecto.Migration

  def change do
    create table(:llm_runs, primary_key: false) do
      add :fingerprint, :string, primary_key: true
      add :profile_id, :string, null: false
      add :profile_name, :string
      add :provider, :string, null: false
      add :model, :string, null: false
      add :policy_version, :string, null: false
      add :resolved_at, :utc_datetime_usec, null: false

      add :overrides, :map, null: false, default: %{}
      add :invocation_config, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:llm_runs, [:profile_id])
    create index(:llm_runs, [:resolved_at])
    create index(:llm_runs, [:provider, :model])
  end

end
