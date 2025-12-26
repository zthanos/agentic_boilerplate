defmodule AgentWeb.Repo.Migrations.RebuildLlmRunsAddRunIdAndCorrelationId do
  use Ecto.Migration

  def up do
    # 1) new table
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

      # existing runtime columns (από το RunRecord σου)
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

    # 2) copy old data -> v2
    # Για υπάρχοντα rows: trace_id = run_id (ώστε να είναι valid)
    # SQLite uuid: randomblob(16) hex. Για :binary_id σε Ecto/SQLite, αποθηκεύεται ως string.
    execute("""
    INSERT INTO llm_runs_v2 (
      run_id, trace_id, parent_run_id, phase,
      fingerprint, profile_id, profile_name, provider, model, policy_version, resolved_at,
      overrides, invocation_config,
      status, started_at, finished_at, error, usage, latency_ms,
      inserted_at, updated_at
    )
    SELECT
      lower(hex(randomblob(16))) as run_id,
      lower(hex(randomblob(16))) as trace_id,
      NULL as parent_run_id,
      NULL as phase,
      fingerprint, profile_id, profile_name, provider, model, policy_version, resolved_at,
      overrides, invocation_config,
      status, started_at, finished_at, error, usage, latency_ms,
      inserted_at, updated_at
    FROM llm_runs
    """)

    # 3) swap
    drop table(:llm_runs)
    rename table(:llm_runs_v2), to: table(:llm_runs)
  end

  def down do
    raise "Irreversible migration (llm_runs rebuilt)."
  end
end
