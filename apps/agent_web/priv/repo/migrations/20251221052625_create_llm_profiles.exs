defmodule AgentWeb.Repo.Migrations.CreateLlmProfiles do
  use Ecto.Migration

  def change do
    create table(:llm_profiles, primary_key: false) do
      add :id, :string, primary_key: true

      add :name, :string
      add :enabled, :boolean, null: false, default: true

      # provider/model are part of the profile identity/config
      add :provider, :string, null: false
      add :model, :string, null: false

      # version/policy control (string identifier)
      add :policy_version, :string

      # JSON-friendly columns (SQLite/Postgres portable)
      add :generation, :map, null: false, default: %{}
      add :budgets, :map, null: false, default: %{}
      add :tools, {:array, :string}, null: false, default: []
      add :stop_list, {:array, :string}, null: false, default: []
      add :tags, {:array, :string}, null: false, default: []

      timestamps(type: :utc_datetime_usec)
    end

    create index(:llm_profiles, [:enabled])
    create index(:llm_profiles, [:provider])
    create index(:llm_profiles, [:model])
  end
end
