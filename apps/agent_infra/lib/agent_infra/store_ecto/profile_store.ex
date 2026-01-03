defmodule AgentInfra.StoreEcto.ProfileStore do
  @moduledoc """
  Ecto implementation of the ProfileStore behavior.

  This module implements the AgentCore.Stores.ProfileStore behavior using Ecto
  and PostgreSQL for persistence. It handles conversion between domain structs
  and database schemas.
  """

  @behaviour AgentCore.Stores.ProfileStore

  alias AgentCore.{Profiles, Stores.ProfileStore}
  alias AgentCore.Profiles.{GenerationParams, Budgets}
  alias AgentInfra.{Repo, Schema.Profile}
  import Ecto.Query

  @impl ProfileStore
  def create(%Profiles{} = profile) do
    attrs = domain_to_schema_attrs(profile)

    %Profile{}
    |> Profile.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, schema} -> {:ok, schema.id}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @impl ProfileStore
  def get(profile_id) do
    case Repo.get(Profile, to_string(profile_id)) do
      nil -> {:error, :not_found}
      schema -> {:ok, schema_to_domain(schema)}
    end
  end

  @impl ProfileStore
  def get_by_name(name) when is_binary(name) do
    query = from(p in Profile, where: p.name == ^name)

    case Repo.one(query) do
      nil -> {:error, :not_found}
      schema -> {:ok, schema_to_domain(schema)}
    end
  end

  @impl ProfileStore
  def update(profile_id, updates) when is_map(updates) do
    case Repo.get(Profile, to_string(profile_id)) do
      nil ->
        {:error, :not_found}

      schema ->
        schema
        |> Profile.changeset(updates)
        |> Repo.update()
        |> case do
          {:ok, updated_schema} -> {:ok, schema_to_domain(updated_schema)}
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  @impl ProfileStore
  def delete(profile_id) do
    case Repo.get(Profile, to_string(profile_id)) do
      nil ->
        {:error, :not_found}

      schema ->
        case Repo.delete(schema) do
          {:ok, _} -> :ok
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  @impl ProfileStore
  def list(opts \\ []) do
    query = build_list_query(opts)

    try do
      profiles =
        query
        |> Repo.all()
        |> Enum.map(&schema_to_domain/1)

      {:ok, profiles}
    rescue
      error -> {:error, error}
    end
  end

  @impl ProfileStore
  def list_enabled do
    query = from(p in Profile, where: p.enabled == true)

    try do
      profiles =
        query
        |> Repo.all()
        |> Enum.map(&schema_to_domain/1)

      {:ok, profiles}
    rescue
      error -> {:error, error}
    end
  end

  @impl ProfileStore
  def list_by_provider(provider) when is_atom(provider) do
    query = from(p in Profile, where: p.provider == ^to_string(provider))

    try do
      profiles =
        query
        |> Repo.all()
        |> Enum.map(&schema_to_domain/1)

      {:ok, profiles}
    rescue
      error -> {:error, error}
    end
  end

  @impl ProfileStore
  def count(opts \\ []) do
    query = build_list_query(opts)

    try do
      count =
        query
        |> select([p], count(p.id))
        |> Repo.one()

      {:ok, count}
    rescue
      error -> {:error, error}
    end
  end

  @impl ProfileStore
  def name_available?(name, exclude_id \\ nil) when is_binary(name) do
    query =
      case exclude_id do
        nil ->
          from(p in Profile, where: p.name == ^name)

        exclude_id ->
          from(p in Profile, where: p.name == ^name and p.id != ^to_string(exclude_id))
      end

    try do
      case Repo.one(query) do
        nil -> {:ok, true}
        _profile -> {:ok, false}
      end
    rescue
      error -> {:error, error}
    end
  end

  @impl ProfileStore
  def set_enabled(profile_id, enabled) when is_boolean(enabled) do
    case __MODULE__.update(profile_id, %{enabled: enabled}) do
      {:ok, profile} -> {:ok, profile}
      error -> error
    end
  end

  @impl ProfileStore
  def search(query_string, opts \\ []) when is_binary(query_string) do
    search_pattern = "%#{query_string}%"

    query =
      from(p in Profile,
        where: ilike(p.name, ^search_pattern)
      )

    query = apply_query_options(query, opts)

    try do
      profiles =
        query
        |> Repo.all()
        |> Enum.map(&schema_to_domain/1)

      {:ok, profiles}
    rescue
      error -> {:error, error}
    end
  end

  # Private helper functions

  defp domain_to_schema_attrs(%Profiles{} = profile) do
    %{
      id: profile.id && to_string(profile.id),
      name: profile.name,
      enabled: profile.enabled,
      provider: to_string(profile.provider),
      model: to_string(profile.model),
      policy_version: profile.policy_version,
      generation: GenerationParams.to_map(profile.generation),
      budgets: Budgets.to_map(profile.budgets),
      tools: Enum.map(profile.tools, &to_string/1),
      stop_list: profile.stop_list,
      tags: profile.tags
    }
  end

  defp schema_to_domain(%Profile{} = schema) do
    %Profiles{
      id: schema.id,
      name: schema.name,
      enabled: schema.enabled,
      provider: String.to_existing_atom(schema.provider),
      model: schema.model,
      policy_version: schema.policy_version,
      generation: GenerationParams.from_map(schema.generation || %{}),
      budgets: Budgets.from_map(schema.budgets || %{}),
      tools: schema.tools || [],
      stop_list: schema.stop_list || [],
      tags: schema.tags || [],
      created_at: schema.inserted_at,
      updated_at: schema.updated_at
    }
  end

  defp build_list_query(opts) do
    base_query = from(p in Profile)

    apply_query_options(base_query, opts)
  end

  defp apply_query_options(query, opts) do
    Enum.reduce(opts, query, fn
      {:enabled, enabled}, q ->
        from(p in q, where: p.enabled == ^enabled)

      {:provider, provider}, q ->
        from(p in q, where: p.provider == ^to_string(provider))

      {:tags, tags}, q when is_list(tags) ->
        # PostgreSQL array overlap operator
        from(p in q, where: fragment("? && ?", p.tags, ^tags))

      {:limit, limit}, q ->
        from(p in q, limit: ^limit)

      {:offset, offset}, q ->
        from(p in q, offset: ^offset)

      {:order_by, :name_asc}, q ->
        from(p in q, order_by: [asc: p.name])

      {:order_by, :name_desc}, q ->
        from(p in q, order_by: [desc: p.name])

      {:order_by, field}, q when is_atom(field) ->
        from(p in q, order_by: [asc: ^field])

      _other, q ->
        q
    end)
  end
end
