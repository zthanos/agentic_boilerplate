defmodule AgentWeb.Repo.Migrations.AddRunLifecycleFields do
  use Ecto.Migration

  def change do
    alter table(:llm_runs) do
      add :status, :string, null: false, default: "created"
      add :started_at, :utc_datetime_usec
      add :finished_at, :utc_datetime_usec
      add :error, :map
      add :usage, :map
      add :latency_ms, :integer
    end

    create index(:llm_runs, [:status])
    create index(:llm_runs, [:started_at])
    create index(:llm_runs, [:finished_at])
  end
end
