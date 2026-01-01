defmodule AgentWeb.Repo.Migrations.CreateConversationMessages do
  use Ecto.Migration

  def change do
    create table(:conversation_messages, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :conversation_id, references(:conversations, type: :uuid, on_delete: :delete_all),
        null: false

      add :role, :string, null: false
      add :content, :text, null: false
      add :run_id, :uuid
      add :seq, :integer, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:conversation_messages, [:conversation_id, :seq])
    create index(:conversation_messages, [:run_id])

    create constraint(:conversation_messages, :role_must_be_valid,
             check: "role in ('user','assistant','system','tool')"
           )
  end
end
