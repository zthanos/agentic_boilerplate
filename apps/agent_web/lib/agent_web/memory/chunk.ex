# apps/agent_web/lib/agent_web/memory/chunk.ex
defmodule AgentWeb.Memory.Chunk do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "memory_chunks" do
    field :conversation_id, :binary_id
    field :chunk_text, :string
    field :chunk_hash, :string
    field :token_count, :integer
    field :embedding, Pgvector.Ecto.Vector
    field :source_message_ids, {:array, :binary_id}
    field :metadata, :map
    field :expires_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(chunk, attrs) do
    chunk
    |> cast(attrs, [:id, :conversation_id, :chunk_text, :chunk_hash, :token_count, :embedding, :source_message_ids, :metadata, :expires_at])
    |> validate_required([:id, :conversation_id, :chunk_text, :chunk_hash, :token_count, :embedding])
  end
end
