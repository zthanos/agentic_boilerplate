defmodule AgentWebWeb.RunHistoryLive do
  use AgentWebWeb, :live_view

  alias AgentRuntime.Llm.Runs

  @default_limit 50
  @max_limit 200

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:limit, @default_limit)
      |> assign(:filters, %{"trace_id" => "", "profile_id" => "", "status" => ""})
      |> assign(:loading, false)
      |> assign(:runs, [])
      |> assign(:error, nil)

    {:ok, load_runs(socket), temporary_assigns: [runs: []]}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    limit =
      params
      |> Map.get("limit", Integer.to_string(@default_limit))
      |> parse_int(@default_limit)
      |> clamp(1, @max_limit)

    filters = %{
      "trace_id" => Map.get(params, "trace_id", ""),
      "profile_id" => Map.get(params, "profile_id", ""),
      "status" => Map.get(params, "status", "")
    }

    socket =
      socket
      |> assign(:limit, limit)
      |> assign(:filters, filters)

    {:noreply, load_runs(socket)}
  end

  # Accept nested payload: %{"filters" => %{...}}
  @impl true
  def handle_event("filter", %{"filters" => filters}, socket) when is_map(filters) do
    apply_filters(socket, filters)
  end

  # Accept flat payload: %{"trace_id" => "...", "profile_id" => "...", "status" => "..."}
  @impl true
  def handle_event("filter", params, socket) when is_map(params) do
    apply_filters(socket, params)
  end

  defp apply_filters(socket, params) do
    filters = %{
      "trace_id" => Map.get(params, "trace_id", ""),
      "profile_id" => Map.get(params, "profile_id", ""),
      "status" => Map.get(params, "status", "")
    }

    {:noreply,
     push_patch(socket,
       to:
         ~p"/runs?limit=#{socket.assigns.limit}&trace_id=#{filters["trace_id"]}&profile_id=#{filters["profile_id"]}&status=#{filters["status"]}"
     )}
  end

  @impl true
  def handle_event("set_limit", %{"limit" => limit}, socket) do
    limit =
      limit
      |> parse_int(socket.assigns.limit)
      |> clamp(1, @max_limit)

    filters = socket.assigns.filters

    {:noreply,
     push_patch(socket,
       to:
         ~p"/runs?limit=#{limit}&trace_id=#{filters["trace_id"]}&profile_id=#{filters["profile_id"]}&status=#{filters["status"]}"
     )}
  end

  defp load_runs(socket) do
    opts =
      []
      |> maybe_kw_put(:trace_id, socket.assigns.filters["trace_id"])
      |> maybe_kw_put(:profile_id, socket.assigns.filters["profile_id"])
      |> maybe_kw_put(:status, socket.assigns.filters["status"])
      |> Keyword.put(:limit, socket.assigns.limit)

    case Runs.list(opts) do
      {:ok, runs} ->
        assign(socket, runs: Enum.map(runs, &normalize_run/1), error: nil)

      {:error, reason} ->
        assign(socket, runs: [], error: inspect(reason))
    end
  end

  # Adapt whatever shape your Runs.list returns (map or struct)
  defp normalize_run(%{} = r) do
    %{
      run_id: get(r, :run_id),
      trace_id: get(r, :trace_id),
      parent_run_id: get(r, :parent_run_id),
      phase: get(r, :phase),
      status: get(r, :status),
      profile_id: get(r, :profile_id),
      profile_name: get(r, :profile_name),
      provider: get(r, :provider),
      model: get(r, :model),
      latency_ms: get(r, :latency_ms),
      inserted_at: get(r, :inserted_at) || get(r, :created_at),
      started_at: get(r, :started_at),
      finished_at: get(r, :finished_at)
    }
  end

  defp get(map, k) when is_map(map) do
    Map.get(map, k) || Map.get(map, to_string(k))
  end

  defp maybe_kw_put(kw, _k, nil), do: kw
  defp maybe_kw_put(kw, _k, ""), do: kw
  defp maybe_kw_put(kw, k, v), do: Keyword.put(kw, k, v)

  defp parse_int(v, default) when is_binary(v) do
    case Integer.parse(v) do
      {n, _} -> n
      :error -> default
    end
  end

  defp clamp(n, min, max) when n < min, do: min
  defp clamp(n, min, max) when n > max, do: max
  defp clamp(n, _min, _max), do: n

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-semibold">LLM Run History</h1>

        <div class="flex items-center gap-2">
          <label class="text-sm">Limit</label>
          <input
            class="border rounded px-2 py-1 w-24"
            type="number"
            min="1"
            max="200"
            value={@limit}
            phx-change="set_limit"
            name="limit"
          />
        </div>
      </div>

      <.form for={%{}} as={:filters} phx-submit="filter" class="mt-4">
        <div class="grid grid-cols-1 md:grid-cols-4 gap-3">
          <input
            class="border rounded px-2 py-2"
            name="trace_id"
            value={@filters["trace_id"]}
            placeholder="trace_id"
          />
          <input
            class="border rounded px-2 py-2"
            name="profile_id"
            value={@filters["profile_id"]}
            placeholder="profile_id"
          />
          <input
            class="border rounded px-2 py-2"
            name="status"
            value={@filters["status"]}
            placeholder="status (created/started/finished/failed)"
          /> <button class="border rounded px-3 py-2" type="submit">Apply</button>
        </div>
      </.form>

      <%= if @error do %>
        <div class="mt-4 border rounded p-3 text-sm"><strong>Error:</strong> {@error}</div>
      <% end %>

      <div class="mt-4 overflow-auto border rounded">
        <table class="min-w-full text-sm">
          <thead class="border-b">
            <tr class="text-left">
              <th class="p-2">run_id</th>

              <th class="p-2">trace_id</th>

              <th class="p-2">phase</th>

              <th class="p-2">status</th>

              <th class="p-2">profile_id</th>

              <th class="p-2">model</th>

              <th class="p-2">latency</th>

              <th class="p-2">started_at</th>

              <th class="p-2">finished_at</th>
            </tr>
          </thead>

          <tbody>
            <%= for r <- @runs do %>
              <tr class="border-b hover:bg-gray-50">
                <td class="p-2 font-mono">
                  <a class="underline" href={~p"/api/runs/#{r.run_id}"} target="_blank">{r.run_id}</a>
                </td>

                <td class="p-2 font-mono">{r.trace_id}</td>

                <td class="p-2">{r.phase}</td>

                <td class="p-2">{r.status}</td>

                <td class="p-2">{r.profile_id}</td>

                <td class="p-2">{r.model}</td>

                <td class="p-2">{format_latency(r.latency_ms)}</td>

                <td class="p-2">{format_dt(r.started_at)}</td>

                <td class="p-2">{format_dt(r.finished_at)}</td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp format_latency(nil), do: ""
  defp format_latency(ms) when is_integer(ms), do: "#{ms} ms"
  defp format_latency(_), do: ""

  defp format_dt(nil), do: ""
  defp format_dt(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_dt(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
  defp format_dt(other) when is_binary(other), do: other
  defp format_dt(_), do: ""
end
