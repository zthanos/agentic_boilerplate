defmodule AgentWeb.Repo.Migrations.LlmPlans do
  use Ecto.Migration

  @moduledoc """
  Creates the `llm_plans` table (a versioned plan definition) and
  adds a foreign‑key‑like pair of columns (`plan_id`, `plan_version`)
  to the existing `llm_runs` table.

  The migration also creates the necessary indexes.
  """

  def change do
    # Use UUID primary key
    create table(:llm_plans, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :plan_id, :string, null: false
      add :version, :integer, null: false
      add :status, :string, null: false, default: "active"
      add :checksum, :string
      add :definition, :map, null: false

      timestamps(type: :utc_datetime_usec)
    end

    # Unique index on (plan_id, version) – guarantees a single row per plan/version.
    create unique_index(:llm_plans, [:plan_id, :version])

    # ------------------------------------------------------------------
    # 2️⃣ Add the plan references to llm_runs
    # ------------------------------------------------------------------
    alter table(:llm_runs) do
      # nullable – not all runs need a plan reference
      add :plan_id, :string
      add :plan_version, :integer
    end

    # Index for fast look‑ups of runs by the (plan_id, plan_version) pair.
    create index(:llm_runs, [:plan_id, :plan_version])
  end
end
