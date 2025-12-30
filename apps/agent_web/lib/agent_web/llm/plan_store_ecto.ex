defmodule AgentWeb.Llm.PlanStoreEcto do
  @behaviour AgentCore.Llm.PlanStore

  import Ecto.Query, only: [from: 2, dynamic: 2]
  alias AgentWeb.Repo
  alias AgentWeb.Llm.PlanRecord
  alias AgentCore.Llm.Plan.Definition

  @impl true
  def get(plan_id, version) do
    q =
      from p in PlanRecord,
        where: p.plan_id == ^plan_id and p.version == ^version,
        limit: 1

    case Repo.one(q) do
      nil -> {:error, :not_found}
      rec -> to_definition(rec)
    end
  end

  @impl true
  def get_latest(plan_id) do
    q =
      from p in PlanRecord,
        where: p.plan_id == ^plan_id,
        order_by: [desc: p.version],
        limit: 1

    case Repo.one(q) do
      nil -> {:error, :not_found}
      rec -> to_definition(rec)
    end
  end

  @impl true
  def list(opts \\ []) do
    plan_id = Keyword.get(opts, :plan_id)
    status = Keyword.get(opts, :status)

    q =
      from p in PlanRecord,
        where: ^dynamic_filters(plan_id, status),
        order_by: [asc: p.plan_id, desc: p.version]

    recs = Repo.all(q)

    defs =
      recs
      |> Enum.map(fn rec ->
        case to_definition(rec) do
          {:ok, d} -> d
          {:error, _} -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    {:ok, defs}
  rescue
    e -> {:error, e}
  end

  @impl true
  def put(%Definition{} = plan) do
    with {:ok, plan} <- Definition.validate(plan) do
      attrs = %{
        plan_id: plan.id,
        version: plan.version,
        status: "active",
        checksum: plan.checksum,
        definition: Definition.to_map(plan)
      }

      %PlanRecord{}
      |> PlanRecord.changeset(attrs)
      |> Repo.insert()
      |> case do
        {:ok, rec} -> to_definition(rec)
        {:error, cs} -> {:error, cs}
      end
    end
  end

  defp dynamic_filters(nil, nil), do: true

  defp dynamic_filters(plan_id, nil) do
    dynamic([p], p.plan_id == ^plan_id)
  end

  defp dynamic_filters(nil, status) do
    dynamic([p], p.status == ^status)
  end

  defp dynamic_filters(plan_id, status) do
    dynamic([p], p.plan_id == ^plan_id and p.status == ^status)
  end

  defp to_definition(%PlanRecord{definition: defmap}) when is_map(defmap) do
    # defmap is JSON-ready; we rely on core from_map/1
    case Definition.from_map(defmap) do
      {:ok, plan} -> {:ok, plan}
      {:error, err} -> {:error, {:invalid_definition, err}}
    end
  end
end
