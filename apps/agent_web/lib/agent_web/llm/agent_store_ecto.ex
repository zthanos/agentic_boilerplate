defmodule AgentWeb.Llm.AgentStoreEcto do
  @behaviour AgentCore.Llm.AgentStore

  import Ecto.Query, only: [from: 2, dynamic: 2]
  alias AgentWeb.Repo
  alias AgentWeb.Llm.AgentRecord
  alias AgentCore.Llm.Agent.Definition

  @impl true
  def get(agent_id, version) do
    q =
      from a in AgentRecord,
        where: a.agent_id == ^agent_id and a.version == ^version,
        limit: 1

    case Repo.one(q) do
      nil -> {:error, :not_found}
      rec -> to_definition(rec)
    end
  end

  @impl true
  def get_latest(agent_id) do
    q =
      from a in AgentRecord,
        where: a.agent_id == ^agent_id,
        order_by: [desc: a.version],
        limit: 1

    case Repo.one(q) do
      nil -> {:error, :not_found}
      rec -> to_definition(rec)
    end
  end

  @impl true
  def list(opts \\ []) do
    agent_id = Keyword.get(opts, :agent_id)
    status = Keyword.get(opts, :status)

    q =
      from a in AgentRecord,
        where: ^filters(agent_id, status),
        order_by: [asc: a.agent_id, desc: a.version]

    recs = Repo.all(q)

    defs =
      Enum.flat_map(recs, fn rec ->
        case to_definition(rec) do
          {:ok, d} -> [d]
          {:error, _} -> []
        end
      end)

    {:ok, defs}
  end

  @impl true
  def put(%Definition{} = agent) do
    with {:ok, agent} <- Definition.validate(agent) do
      attrs = %{
        # This is the agent_id from your Definition
        agent_id: agent.id,
        version: agent.version,
        status: "active",
        checksum: agent.checksum,
        definition: Definition.to_map(agent)
      }

      %AgentRecord{}
      |> AgentRecord.changeset(attrs)
      |> Repo.insert()
      |> case do
        {:ok, rec} -> to_definition(rec)
        {:error, cs} -> {:error, cs}
      end
    end
  end

  defp filters(nil, nil), do: true
  defp filters(agent_id, nil), do: dynamic([a], a.agent_id == ^agent_id)
  defp filters(nil, status), do: dynamic([a], a.status == ^status)

  defp filters(agent_id, status),
    do: dynamic([a], a.agent_id == ^agent_id and a.status == ^status)

  defp to_definition(%AgentRecord{definition: defmap}) when is_map(defmap) do
    case Definition.from_map(defmap) do
      {:ok, agent} -> {:ok, agent}
      {:error, err} -> {:error, {:invalid_definition, err}}
    end
  end
end
