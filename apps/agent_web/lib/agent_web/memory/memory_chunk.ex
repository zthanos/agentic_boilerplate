defmodule AgentWeb.Memory.MemoryChunk do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "memory_chunks" do
    field :conversation_id, Ecto.UUID
    field :chunk_text, :string
    field :chunk_hash, :string
    field :token_count, :integer
    field :embedding, Pgvector.Ecto.Vector
    field :source_message_ids, {:array, Ecto.UUID}, default: []
    field :metadata, :map, default: %{}
    field :expires_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(ch, attrs) do
    ch
    |> cast(attrs, [
      :id, :conversation_id, :chunk_text, :chunk_hash, :token_count,
      :embedding, :source_message_ids, :metadata, :expires_at
    ])
    |> validate_required([:id, :conversation_id, :chunk_text, :chunk_hash, :token_count])
  end
end
