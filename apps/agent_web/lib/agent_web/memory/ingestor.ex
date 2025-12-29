defmodule AgentWeb.Memory.Ingestor do
  alias AgentWeb.Repo
  alias AgentWeb.Memory.MemoryChunk
  alias AgentRuntime.Llm.Executor

  @embeddings_profile_id "embeddings_nomic_v15"

  def ingest_turn!(conversation_id, user_msg, assistant_msg) do
    chunk_text =
      [
        "User: " <> user_msg.content,
        "Assistant: " <> assistant_msg.content
      ]
      |> Enum.join("\n\n")

    chunk_hash = :crypto.hash(:sha256, chunk_text) |> Base.encode16(case: :lower)
    token_count = estimate_tokens(chunk_text)

    {:ok, embedding} =
      Executor.embed(
        profile_id: @embeddings_profile_id,
        input: chunk_text
      )

    Repo.insert!(
      %MemoryChunk{}
      |> MemoryChunk.changeset(%{
        id: Ecto.UUID.generate(),
        conversation_id: conversation_id,
        chunk_text: chunk_text,
        chunk_hash: chunk_hash,
        token_count: token_count,
        embedding: embedding,
        source_message_ids: [user_msg.id, assistant_msg.id],
        metadata: %{"kind" => "turn_v1"}
      }),
      on_conflict: :nothing,
      conflict_target: [:conversation_id, :chunk_hash]
    )
  end

  # v1 heuristic: good enough to start; replace later with real tokenizer if needed
  defp estimate_tokens(text) when is_binary(text) do
    text
    |> String.split(~r/\s+/, trim: true)
    |> length()
  end
end
