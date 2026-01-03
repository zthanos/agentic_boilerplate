defmodule AgentInfra.Repo.Migrations.CreateConversations do
  use Ecto.Migration

  def change do
    create table(:conversations, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, :string, null: false
      add :title, :string
      timestamps(type: :utc_datetime_usec)
    end

    create index(:conversations, [:user_id])
  end
end
