defmodule AgentWeb.Memory.Store do
  import Ecto.Query

  alias AgentWeb.Repo
  alias AgentWeb.Memory.MemoryChunk

  def search(conversation_id, embedding, top_k) do
    from(mc in MemoryChunk,
      where: mc.conversation_id == ^conversation_id,
      where: is_nil(mc.expires_at) or mc.expires_at > ^DateTime.utc_now(),
      select: %{
        id: mc.id,
        text: mc.chunk_text,
        score: fragment("1 - (embedding <=> ?)", ^embedding)
      },
      order_by: fragment("embedding <=> ?", ^embedding),
      limit: ^top_k
    )
    |> Repo.all()
  end
end
