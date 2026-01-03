defmodule AgentInfra.StoreEcto.MemoryChunkStore do
  @moduledoc """
  Ecto implementation for memory chunk storage.

  This module provides CRUD operations for memory chunks using Ecto
  and PostgreSQL with pgvector for persistence and vector similarity search.
  """

  alias AgentInfra.{Repo, Schema.MemoryChunk}
  import Ecto.Query

  @type chunk_id :: String.t()
  @type conversation_id :: String.t()
  @type error :: term()

  @doc """
  Creates a new memory chunk.
  """
  @spec create(map()) :: {:ok, MemoryChunk.t()} | {:error, error()}
  def create(attrs) when is_map(attrs) do
    %MemoryChunk{}
    |> MemoryChunk.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Retrieves a memory chunk by ID.
  """
  @spec get(chunk_id()) :: {:ok, MemoryChunk.t()} | {:error, :not_found}
  def get(chunk_id) when is_binary(chunk_id) do
    case Repo.get(MemoryChunk, chunk_id) do
      nil -> {:error, :not_found}
      chunk -> {:ok, chunk}
    end
  end

  @doc """
  Updates a memory chunk.
  """
  @spec update(chunk_id(), map()) :: {:ok, MemoryChunk.t()} | {:error, error()}
  def update(chunk_id, updates) when is_binary(chunk_id) and is_map(updates) do
    case Repo.get(MemoryChunk, chunk_id) do
      nil ->
        {:error, :not_found}

      chunk ->
        chunk
        |> MemoryChunk.changeset(updates)
        |> Repo.update()
    end
  end

  @doc """
  Deletes a memory chunk.
  """
  @spec delete(chunk_id()) :: :ok | {:error, error()}
  def delete(chunk_id) when is_binary(chunk_id) do
    case Repo.get(MemoryChunk, chunk_id) do
      nil ->
        {:error, :not_found}

      chunk ->
        case Repo.delete(chunk) do
          {:ok, _} -> :ok
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  @doc """
  Lists memory chunks for a conversation.
  """
  @spec list_by_conversation(conversation_id()) :: {:ok, [MemoryChunk.t()]} | {:error, error()}
  def list_by_conversation(conversation_id) when is_binary(conversation_id) do
    query =
      from(m in MemoryChunk,
        where: m.conversation_id == ^conversation_id,
        order_by: [desc: m.inserted_at]
      )

    try do
      chunks = Repo.all(query)
      {:ok, chunks}
    rescue
      error -> {:error, error}
    end
  end

  @doc """
  Performs similarity search using vector embeddings.
  """
  @spec similarity_search(list(float()), keyword()) ::
          {:ok, [MemoryChunk.t()]} | {:error, error()}
  def similarity_search(query_embedding, opts \\ []) when is_list(query_embedding) do
    limit = Keyword.get(opts, :limit, 10)
    threshold = Keyword.get(opts, :threshold, 0.7)
    conversation_id = Keyword.get(opts, :conversation_id)

    query =
      from(m in MemoryChunk,
        order_by: fragment("? <-> ?", m.embedding, ^query_embedding),
        where: fragment("? <-> ? < ?", m.embedding, ^query_embedding, ^(1.0 - threshold)),
        limit: ^limit
      )

    query =
      if conversation_id do
        from(m in query, where: m.conversation_id == ^conversation_id)
      else
        query
      end

    try do
      chunks = Repo.all(query)
      {:ok, chunks}
    rescue
      error -> {:error, error}
    end
  end

  @doc """
  Deletes expired memory chunks.
  """
  @spec delete_expired() :: {:ok, integer()} | {:error, error()}
  def delete_expired do
    now = DateTime.utc_now()

    query =
      from(m in MemoryChunk,
        where: not is_nil(m.expires_at) and m.expires_at < ^now
      )

    try do
      {count, _} = Repo.delete_all(query)
      {:ok, count}
    rescue
      error -> {:error, error}
    end
  end

  @doc """
  Lists all memory chunks with pagination.
  """
  @spec list(keyword()) :: {:ok, [MemoryChunk.t()]} | {:error, error()}
  def list(opts \\ []) do
    query =
      from(m in MemoryChunk,
        order_by: [desc: m.inserted_at]
      )

    query = apply_pagination(query, opts)

    try do
      chunks = Repo.all(query)
      {:ok, chunks}
    rescue
      error -> {:error, error}
    end
  end

  defp apply_pagination(query, opts) do
    Enum.reduce(opts, query, fn
      {:limit, limit}, q -> from(m in q, limit: ^limit)
      {:offset, offset}, q -> from(m in q, offset: ^offset)
      _other, q -> q
    end)
  end
end
