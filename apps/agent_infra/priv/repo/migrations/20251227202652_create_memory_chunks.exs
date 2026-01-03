defmodule AgentInfra.Repo.Migrations.CreateMemoryChunks do
  use Ecto.Migration

  @embedding_dim 768

  def change do
    create table(:memory_chunks, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :conversation_id,
          references(:conversations, type: :uuid, on_delete: :delete_all),
          null: false

      add :chunk_text, :text, null: false
      add :chunk_hash, :string, null: false
      add :token_count, :integer, null: false

      add :embedding, :"vector(#{@embedding_dim})"

      add :source_message_ids, {:array, :uuid}, null: false, default: []
      add :metadata, :map, null: false, default: %{}
      add :expires_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:memory_chunks, [:conversation_id, :chunk_hash])
    create index(:memory_chunks, [:conversation_id, :inserted_at])

    execute(
      """
      CREATE INDEX memory_chunks_embedding_hnsw
      ON memory_chunks
      USING hnsw (embedding vector_cosine_ops)
      """,
      "DROP INDEX IF EXISTS memory_chunks_embedding_hnsw"
    )
  end
end
