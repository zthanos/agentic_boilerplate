# apps/agent_web/lib/agent_web/memory/store.ex
defmodule AgentWeb.Memory.Store do
  @behaviour AgentRuntime.Memory.Store

  require Logger
  import Ecto.Query

  alias AgentWeb.Repo
  alias AgentWeb.Memory.Chunk

  @impl true
  def search(conversation_id, embedding, top_k) when is_binary(conversation_id) do
    # Use Ecto query with fragment for pgvector operations
    query =
      from c in Chunk,
        where: c.conversation_id == ^conversation_id,
        select: %{
          id: c.id,
          text: c.chunk_text,
          score: fragment("1 - (embedding <=> ?) as score", ^embedding)
        },
        order_by: [asc: fragment("embedding <=> ?", ^embedding)],
        limit: ^top_k

    try do
      results = Repo.all(query)

      Enum.map(results, fn result ->
        %{
          id: result.id,
          text: result.text,
          score: result.score || 0.0
        }
      end)
    rescue
      e ->
        Logger.error("Memory search error: #{Exception.message(e)}")
        []
    end
  end

  def search(_conversation_id, _embedding, _top_k), do: []
end
