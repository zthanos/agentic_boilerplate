defmodule AgentWebWeb.RunController do
  use AgentWebWeb, :controller

  alias AgentRuntime.Llm.Runs

  # GET /api/runs?limit=50&trace_id=...&fingerprint=...&profile_id=...&status=...
  def index(conn, params) do
    limit =
      params
      |> Map.get("limit", "50")
      |> to_int(50)
      |> clamp(1, 200)

    filters =
      %{}
      |> maybe_put("trace_id", params["trace_id"])
      |> maybe_put("fingerprint", params["fingerprint"])
      |> maybe_put("profile_id", params["profile_id"])
      |> maybe_put("status", params["status"])
      |> Map.to_list()
      |> Keyword.new()
      |> Keyword.put(:limit, limit)

    case Runs.list(filters) do
      {:ok, runs} ->
        data = Enum.map(runs, &to_run_json/1)
        json(conn, %{data: data, meta: %{limit: limit, count: length(data)}})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "runs_list_failed", reason: inspect(reason)})
    end
  end

  # GET /api/runs/:run_id
  def show(conn, %{"run_id" => run_id}) do
    case Runs.get(run_id) do
      {:ok, snap} ->
        json(conn, %{data: to_run_json(snap)})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: %{message: "run not found", run_id: run_id}})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: %{message: "failed to fetch run", reason: inspect(reason)}})
    end
  end



  # Stable, UI-friendly JSON shape.
  defp to_run_json(snap) do
    %{
      run_id: snap.run_id,
      trace_id: snap.trace_id,
      parent_run_id: snap.parent_run_id,
      phase: snap.phase,

      fingerprint: snap.fingerprint,
      profile_id: snap.profile_id,
      profile_name: snap.profile_name,
      provider: snap.provider,
      model: snap.model,
      policy_version: snap.policy_version,
      resolved_at: snap.resolved_at,
      overrides: snap.overrides,
      invocation_config: snap.invocation_config
    }
  end

  defp maybe_put(map, _k, nil), do: map
  defp maybe_put(map, _k, ""), do: map
  defp maybe_put(map, k, v), do: Map.put(map, String.to_existing_atom(k), v)

  defp to_int(v, default) when is_binary(v) do
    case Integer.parse(v) do
      {n, _} -> n
      :error -> default
    end
  end

  defp clamp(n, min, _max) when n < min, do: min
  defp clamp(n, _min, max) when n > max, do: max
  defp clamp(n, _min, _max), do: n
end
