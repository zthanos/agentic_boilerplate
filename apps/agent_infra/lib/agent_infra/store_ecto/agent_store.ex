defmodule AgentInfra.StoreEcto.AgentStore do
  @moduledoc """
  Ecto implementation of the AgentStore behavior.

  This module implements the AgentCore.Llm.AgentStore behavior using Ecto
  and PostgreSQL for persistence. It handles conversion between domain structs
  and database schemas.
  """

  @behaviour AgentCore.Llm.AgentStore

  alias AgentCore.Llm.{AgentStore, Agent.Definition}
  alias AgentInfra.{Repo, Schema.Agent}
  import Ecto.Query

  @impl AgentStore
  def get(agent_id, version) when is_binary(agent_id) do
    query =
      from(a in Agent,
        where: a.agent_id == ^agent_id and a.version == ^version,
        limit: 1
      )

    case Repo.one(query) do
      nil -> {:error, :not_found}
      schema -> {:ok, schema_to_domain(schema)}
    end
  end

  @impl AgentStore
  def get_latest(agent_id) when is_binary(agent_id) do
    query =
      from(a in Agent,
        where: a.agent_id == ^agent_id and a.status == "active",
        order_by: [desc: a.version],
        limit: 1
      )

    case Repo.one(query) do
      nil -> {:error, :not_found}
      schema -> {:ok, schema_to_domain(schema)}
    end
  end

  @impl AgentStore
  def put(%Definition{} = definition) do
    attrs = domain_to_schema_attrs(definition)

    %Agent{}
    |> Agent.changeset(attrs)
    |> Repo.insert_or_update()
    |> case do
      {:ok, schema} -> {:ok, schema_to_domain(schema)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @impl AgentStore
  def list(opts \\ []) do
    query = build_list_query(opts)

    try do
      agents =
        query
        |> Repo.all()
        |> Enum.map(&schema_to_domain/1)

      {:ok, agents}
    rescue
      error -> {:error, error}
    end
  end

  # Private helper functions

  defp domain_to_schema_attrs(%Definition{} = definition) do
    %{
      agent_id: definition.id,
      version: definition.version,
      # Default status
      status: "active",
      checksum: definition.checksum,
      definition: definition
    }
  end

  defp schema_to_domain(%Agent{} = schema) do
    # The definition field contains the full Definition struct
    definition = schema.definition

    # Ensure we have a proper Definition struct
    case definition do
      %Definition{} = def_struct ->
        def_struct

      definition_map when is_map(definition_map) ->
        # Fix the plan version if it's causing issues
        fixed_definition_map = fix_plan_version(definition_map)

        # Use the Definition.from_map function to properly convert
        case Definition.from_map(fixed_definition_map) do
          {:ok, def_struct} ->
            def_struct

          {:error, _error} ->
            # Fallback if conversion fails
            %Definition{
              id: schema.agent_id,
              version: schema.version,
              checksum: schema.checksum,
              plan: %{id: "default", version: :latest}
            }
        end

      _ ->
        # Fallback: create a basic Definition struct
        %Definition{
          id: schema.agent_id,
          version: schema.version,
          checksum: schema.checksum,
          plan: %{id: "default", version: :latest}
        }
    end
  end

  defp fix_plan_version(definition_map) do
    case get_in(definition_map, ["plan", "version"]) do
      "latest" -> put_in(definition_map, ["plan", "version"], :latest)
      # Already correct
      :latest -> definition_map
      # Already correct
      version when is_integer(version) -> definition_map
      # Leave as is
      _ -> definition_map
    end
  end

  defp build_list_query(opts) do
    base_query = from(a in Agent)

    apply_query_options(base_query, opts)
  end

  defp apply_query_options(query, opts) do
    Enum.reduce(opts, query, fn
      {:agent_id, agent_id}, q ->
        from(a in q, where: a.agent_id == ^agent_id)

      {:status, status}, q ->
        from(a in q, where: a.status == ^status)

      {:version, version}, q ->
        from(a in q, where: a.version == ^version)

      {:limit, limit}, q ->
        from(a in q, limit: ^limit)

      {:offset, offset}, q ->
        from(a in q, offset: ^offset)

      {:order_by, :version_desc}, q ->
        from(a in q, order_by: [desc: a.version])

      {:order_by, :version_asc}, q ->
        from(a in q, order_by: [asc: a.version])

      {:order_by, field}, q when is_atom(field) ->
        from(a in q, order_by: [desc: ^field])

      _other, q ->
        q
    end)
  end
end
