defmodule AgentInfra.StoreEcto.ConversationStore do
  @moduledoc """
  Ecto implementation for conversation storage.

  This module provides CRUD operations for conversations using Ecto
  and PostgreSQL for persistence.
  """

  alias AgentInfra.{Repo, Schema.Conversation}
  import Ecto.Query

  @type conversation_id :: String.t()
  @type error :: term()

  @doc """
  Creates a new conversation.
  """
  @spec create(map()) :: {:ok, Conversation.t()} | {:error, error()}
  def create(attrs) when is_map(attrs) do
    %Conversation{}
    |> Conversation.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Retrieves a conversation by ID.
  """
  @spec get(conversation_id()) :: {:ok, Conversation.t()} | {:error, :not_found}
  def get(conversation_id) when is_binary(conversation_id) do
    case Repo.get(Conversation, conversation_id) do
      nil -> {:error, :not_found}
      conversation -> {:ok, conversation}
    end
  end

  @doc """
  Updates a conversation.
  """
  @spec update(conversation_id(), map()) :: {:ok, Conversation.t()} | {:error, error()}
  def update(conversation_id, updates) when is_binary(conversation_id) and is_map(updates) do
    case Repo.get(Conversation, conversation_id) do
      nil ->
        {:error, :not_found}

      conversation ->
        conversation
        |> Conversation.changeset(updates)
        |> Repo.update()
    end
  end

  @doc """
  Deletes a conversation.
  """
  @spec delete(conversation_id()) :: :ok | {:error, error()}
  def delete(conversation_id) when is_binary(conversation_id) do
    case Repo.get(Conversation, conversation_id) do
      nil ->
        {:error, :not_found}

      conversation ->
        case Repo.delete(conversation) do
          {:ok, _} -> :ok
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  @doc """
  Lists conversations for a user.
  """
  @spec list_by_user(String.t()) :: {:ok, [Conversation.t()]} | {:error, error()}
  def list_by_user(user_id) when is_binary(user_id) do
    query =
      from(c in Conversation,
        where: c.user_id == ^user_id,
        order_by: [desc: c.inserted_at]
      )

    try do
      conversations = Repo.all(query)
      {:ok, conversations}
    rescue
      error -> {:error, error}
    end
  end

  @doc """
  Lists all conversations with pagination.
  """
  @spec list(keyword()) :: {:ok, [Conversation.t()]} | {:error, error()}
  def list(opts \\ []) do
    query =
      from(c in Conversation,
        order_by: [desc: c.inserted_at]
      )

    query = apply_pagination(query, opts)

    try do
      conversations = Repo.all(query)
      {:ok, conversations}
    rescue
      error -> {:error, error}
    end
  end

  defp apply_pagination(query, opts) do
    Enum.reduce(opts, query, fn
      {:limit, limit}, q -> from(c in q, limit: ^limit)
      {:offset, offset}, q -> from(c in q, offset: ^offset)
      _other, q -> q
    end)
  end
end
