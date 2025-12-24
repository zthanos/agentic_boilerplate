defmodule AgentWebWeb.RunController do
  use AgentWebWeb, :controller

  alias AgentRuntime.Llm.Runs


  # GET /api/runs?limit=50
  def index(conn, params) do
    limit =
      params
      |> Map.get("limit", "50")
      |> to_int(50)
      |> clamp(1, 200)

      case Runs.list(limit: limit) do
        {:ok, runs} ->
          runs |> dbg
          json(conn, %{data: runs, meta: %{limit: limit, count: length(runs)}})

        {:error, reason} ->
          conn
          |> put_status(500)
          |> json(%{error: "runs_list_failed", reason: inspect(reason)})
      end

  end

  # GET /api/runs/:fingerprint
  def show(conn, %{"fingerprint" => fp}) do
    case Runs.get_by_fingerprint(fp) do
      {:ok, snap} ->
        json(conn, %{data: to_run_json(snap)})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: %{message: "run not found", fingerprint: fp}})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: %{message: "failed to fetch run", reason: inspect(reason)}})
    end
  end

  # Stable, UI-friendly JSON shape.
  # Note: RunSnapshot currently includes base config fields; lifecycle fields (status/latency/usage)
  # live in RunRecord. If you want them, we’ll extend RunStore.get/list later to include them.
  defp to_run_json(snap) do
    %{
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
