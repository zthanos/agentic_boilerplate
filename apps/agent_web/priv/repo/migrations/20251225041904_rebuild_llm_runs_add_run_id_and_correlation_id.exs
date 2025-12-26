defmodule AgentWeb.Repo.Migrations.RebuildLlmRunsAddRunIdAndCorrelationId do
  use Ecto.Migration

  def up do
    # 1) create new table with correct structure
    create table(:llm_runs_v2, primary_key: false) do
      add :run_id, :binary_id, primary_key: true
      add :trace_id, :binary_id, null: false
      add :parent_run_id, :binary_id
      add :phase, :string

      add :fingerprint, :string, null: false
      add :profile_id, :string, null: false
      add :profile_name, :string
      add :provider, :string, null: false
      add :model, :string, null: false
      add :policy_version, :string, null: false
      add :resolved_at, :utc_datetime_usec, null: false

      add :overrides, :map, null: false, default: %{}
      add :invocation_config, :map, null: false, default: %{}

      add :status, :string
      add :started_at, :utc_datetime_usec
      add :finished_at, :utc_datetime_usec
      add :error, :map
      add :usage, :map
      add :latency_ms, :integer

      timestamps(type: :utc_datetime_usec)
    end

    create index(:llm_runs_v2, [:fingerprint])
    create index(:llm_runs_v2, [:profile_id])
    create index(:llm_runs_v2, [:resolved_at])
    create index(:llm_runs_v2, [:provider, :model])
    create index(:llm_runs_v2, [:trace_id, :inserted_at])
    create index(:llm_runs_v2, [:parent_run_id])

    # 2) drop old table (no data migration)
    drop table(:llm_runs)

    # 3) rename v2 → llm_runs
    rename table(:llm_runs_v2), to: table(:llm_runs)
  end

  def down do
    raise "Irreversible migration (llm_runs rebuilt without data migration)."
  end
end
