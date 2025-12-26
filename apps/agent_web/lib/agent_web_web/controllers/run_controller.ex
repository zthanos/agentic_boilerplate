defmodule AgentWebWeb.RunController do
  use AgentWebWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias AgentRuntime.Llm.Runs
  alias AgentWeb.OpenApi.Schemas

  operation :index,
    summary: "List runs",
    parameters: [
      limit: [in: :query, description: "Max items (1-200), default 50", type: :integer, required: false],
      trace_id: [in: :query, description: "Filter by trace_id", type: :string, required: false],
      fingerprint: [in: :query, description: "Filter by fingerprint", type: :string, required: false],
      profile_id: [in: :query, description: "Filter by profile_id", type: :string, required: false],
      status: [in: :query, description: "Filter by status", type: :string, required: false]
    ],
    responses: [
      ok: {"OK", "application/json", Schemas.RunsIndexResponse},
      internal_server_error: {"Internal Server Error", "application/json", Schemas.ApiError}
    ]

  operation :show,
    summary: "Get run by run_id",
    parameters: [
      run_id: [in: :path, description: "Run ID", type: :string, required: true]
    ],
    responses: [
      ok: {"OK", "application/json", Schemas.RunShowResponse},
      not_found: {"Not Found", "application/json", Schemas.ApiError},
      internal_server_error: {"Internal Server Error", "application/json", Schemas.ApiError}
    ]

  # GET /api/runs?limit=50&trace_id=...&fingerprint=...&profile_id=...&status=...
  def index(conn, params) do
    limit =
      params
      |> Map.get("limit", "50")
      |> to_int(50)
      |> clamp(1, 200)

    opts =
      []
      |> maybe_kw_put(:trace_id, params["trace_id"])
      |> maybe_kw_put(:fingerprint, params["fingerprint"])
      |> maybe_kw_put(:profile_id, params["profile_id"])
      |> maybe_kw_put(:status, params["status"])
      |> Keyword.put(:limit, limit)

    case Runs.list(opts) do
      {:ok, runs} ->
        data = Enum.map(runs, &to_run_json/1)
        json(conn, %{data: data, meta: %{limit: limit, count: length(data)}})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{status: "error", error: %{message: "runs_list_failed", reason: inspect(reason)}})
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
        |> json(%{status: "error", error: %{message: "run_not_found", run_id: run_id}})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{status: "error", error: %{message: "runs_get_failed", reason: inspect(reason)}})
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
      provider: to_string(snap.provider),
      model: to_string(snap.model),
      policy_version: snap.policy_version,
      resolved_at: snap.resolved_at,
      overrides: snap.overrides,
      invocation_config: snap.invocation_config
    }
  end

  defp maybe_kw_put(kw, _k, nil), do: kw
  defp maybe_kw_put(kw, _k, ""), do: kw
  defp maybe_kw_put(kw, k, v), do: Keyword.put(kw, k, v)

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
