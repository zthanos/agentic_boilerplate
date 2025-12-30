defmodule AgentWebWeb.AgentController do
  use AgentWebWeb, :controller

  alias AgentRuntime.Llm.Agent.Store, as: AgentStoreDI

  def index(conn, params) do
    # Optional filters
    agent_id = Map.get(params, "agent_id")
    status = Map.get(params, "status", "active")

    store = AgentStoreDI.impl!()

    with {:ok, agents} <- store.list(agent_id: agent_id, status: status) do
      json(conn, %{
        "data" =>
          Enum.map(agents, fn a ->
            %{
              "agent_id" => a.id,
              "version" => a.version,
              "name" => a.name,
              "description" => a.description,
              "plan" => a.plan,
              "profiles" => a.profiles,
              "metadata" => a.metadata
            }
          end)
      })
    else
      {:error, reason} ->
        conn |> put_status(:internal_server_error) |> json(%{"error" => inspect(reason)})
    end
  end

  def show_latest(conn, %{"agent_id" => agent_id}) do
    store = AgentStoreDI.impl!()

    case store.get_latest(agent_id) do
      {:ok, a} ->
        json(conn, %{
          "data" => %{
            "agent_id" => a.id,
            "version" => a.version,
            "name" => a.name,
            "description" => a.description,
            "plan" => a.plan,
            "profiles" => a.profiles,
            "prompts" => a.prompts,
            "policies" => a.policies,
            "metadata" => a.metadata
          }
        })

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{"error" => "not_found"})

      {:error, reason} ->
        conn |> put_status(:internal_server_error) |> json(%{"error" => inspect(reason)})
    end
  end
end
