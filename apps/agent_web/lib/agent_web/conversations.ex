defmodule AgentWeb.Conversations do
  @behaviour AgentRuntime.Llm.Conversations

  import Ecto.Query
  alias AgentWeb.Repo
  alias AgentWeb.Conversations.{Conversation, ConversationMessage}

  @doc "Creates the conversation row if missing (id is client-generated UUID)."
  def ensure_conversation!(conversation_id, user_id) do
    now = DateTime.utc_now()

    Repo.insert!(
      %Conversation{id: conversation_id, user_id: user_id, inserted_at: now, updated_at: now},
      on_conflict: :nothing,
      conflict_target: [:id]
    )
  end

  @doc "Appends a message with sequential ordering per conversation."
  def append_message!(conversation_id, role, content, run_id \\ nil) do
    Repo.transaction(fn ->
      seq =
        Repo.one(
          from m in ConversationMessage,
            where: m.conversation_id == ^conversation_id,
            select: coalesce(max(m.seq), 0)
        ) + 1

      msg =
        %ConversationMessage{}
        |> ConversationMessage.changeset(%{
          id: Ecto.UUID.generate(),
          conversation_id: conversation_id,
          role: role,
          content: content,
          run_id: run_id,
          seq: seq
        })
        |> Repo.insert!()

      msg
    end)
    |> case do
      {:ok, msg} -> msg
      {:error, err} -> raise err
    end
  end
end
