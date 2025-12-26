defmodule AgentWebWeb.ChatExecuteLive do
  use AgentWebWeb, :live_view
  alias AgentWeb.Llm.ProfileStoreEcto

  @default_profile_id "req_llm"

  # 32-hex trace id
  defp new_trace_id do
    Ecto.UUID.generate()
  end


  @impl true
  def mount(_params, _session, socket) do
    trace_id = new_trace_id()

    profiles = ProfileStoreEcto.list([])


    selected_profile_id =
      cond do
        Enum.any?(profiles, &(&1.id == @default_profile_id)) ->
          @default_profile_id

        profiles != [] ->
          hd(profiles).id

        true ->
          @default_profile_id
      end

    {:ok,
     socket
     |> assign(:profiles, profiles)
     |> assign(:profile_id, selected_profile_id)
     |> assign(:trace_id, trace_id)
     |> assign(:phase, "")
     |> assign(:prompt, "hi")
     |> assign(:messages, [])
     |> assign(:last_run_id, nil)
     |> assign(:loading, false)
     |> assign(:result, nil)
     |> assign(:error, nil)
     |> assign(:streaming, false)
     |> assign(:stream_buffer, "")}
  end


  @impl true
  def handle_event("execute", params, socket) do
    requested_profile_id = Map.get(params, "profile_id", socket.assigns.profile_id)

    profile_id =
      if Enum.any?(socket.assigns.profiles, &(&1.id == requested_profile_id)) do
        requested_profile_id
      else
        socket.assigns.profile_id
      end

    phase = Map.get(params, "phase", "")
    prompt = Map.get(params, "prompt", "") |> to_string() |> String.trim()

    trace_id_param = Map.get(params, "trace_id", "") |> to_string() |> String.trim()
    trace_id = if trace_id_param == "", do: socket.assigns.trace_id, else: trace_id_param

    messages0 = Map.get(socket.assigns, :messages, [])
    last_run_id = Map.get(socket.assigns, :last_run_id, nil)

    socket =
      socket
      |> assign(:loading, true)
      |> assign(:error, nil)
      |> assign(:result, nil)
      |> assign(:profile_id, profile_id)
      |> assign(:phase, phase)
      |> assign(:trace_id, trace_id)

    if prompt == "" do
      {:noreply, assign(socket, :loading, false)}
    else
      messages =
        messages0
        |> append_msg("user", prompt)

      input = %{
        "type" => "chat",
        "messages" => messages
      }

      payload =
        %{
          "profile_id" => profile_id,
          "input" => input,
          "overrides" => %{},
          "trace_id" => trace_id
        }
        |> maybe_put("parent_run_id", last_run_id)
        |> maybe_put("phase", blank_to_nil(phase))

      {:noreply,
       socket
       |> assign(:messages, messages)
       |> assign(:streaming, true)
       |> assign(:stream_buffer, "")
       |> assign(:prompt, "")
       |> assign(:loading, false)
       |> push_event("sse_start", %{url: "/api/llm/execute/stream", payload: payload})}
    end
  rescue
    _e in Ecto.NoResultsError ->
      {:noreply, assign(socket, loading: false, error: %{message: "profile_not_found"})}

    e ->
      {:noreply, assign(socket, loading: false, error: %{message: Exception.message(e)})}
  end

  @impl true
  def handle_event("sse_token", %{"token" => token}, socket) do
    buf = (socket.assigns.stream_buffer || "") <> (token || "")
    {:noreply, assign(socket, :stream_buffer, buf)}
  end

  @impl true
  def handle_event("sse_done", payload, socket) do
    # Support both shapes:
    # 1) %{ "meta" => %{...} }  (hook style)
    # 2) %{ "run_id" => "...", "trace_id" => "...", ... } (flat style)
    meta =
      case payload do
        %{"meta" => m} when is_map(m) -> m
        m when is_map(m) -> m
        _ -> %{}
      end

    run_id = Map.get(meta, "run_id")
    trace_id = Map.get(meta, "trace_id")

    assistant_text =
      socket.assigns.stream_buffer
      |> to_string()
      |> String.trim()

    messages =
      socket.assigns.messages
      |> append_msg("assistant", assistant_text)

    result = %{
      status: "ok",
      output_text: assistant_text,
      usage: Map.get(meta, "usage"),
      run_id: run_id,
      trace_id: trace_id,
      fingerprint: Map.get(meta, "fingerprint"),
      latency_ms: Map.get(meta, "latency_ms")
    }

    {:noreply,
     socket
     |> assign(:messages, messages)
     |> assign(:last_run_id, run_id)
     |> assign(:result, result)
     |> assign(:streaming, false)
     |> assign(:stream_buffer, "")}
  end

  @impl true
  def handle_event("sse_error", payload, socket) do
    err =
      case payload do
        %{"error" => e} -> e
        other -> other
      end

    {:noreply,
     socket
     |> assign(:streaming, false)
     |> assign(:loading, false)
     |> assign(:error, %{message: inspect(err), meta: payload})}
  end

  # --- helpers ---

  defp append_msg(messages, role, content) do
    content = (content || "") |> to_string() |> String.trim()

    if content == "" do
      messages
    else
      messages ++ [%{"role" => role, "content" => content}]
    end
  end

  defp maybe_put(map, _k, nil), do: map
  defp maybe_put(map, _k, ""), do: map
  defp maybe_put(map, k, v), do: Map.put(map, k, v)

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(v), do: v

  defp bubble_class("user"),
    do: "p-3 rounded border text-sm bg-slate-900 border-slate-700"

  defp bubble_class("assistant"),
    do: "p-3 rounded border text-sm bg-slate-950 border-slate-700"

  defp bubble_class(_),
    do: "p-3 rounded border text-sm bg-slate-900 border-slate-700"

  @impl true
  def render(assigns) do
    ~H"""
    <div id="llm-chat" phx-hook="LlmSSE" class="min-h-screen p-6 bg-slate-900 text-slate-100">
      <div class="max-w-5xl mx-auto">
        <div class="flex items-center justify-between">
          <div>
            <h1 class="text-2xl font-semibold">LLM Execute</h1>
            <div class="text-xs text-slate-400 mt-1">
              session trace_id:
              <span class="font-mono"><%= @trace_id %></span>
              <span class="mx-2">•</span>
              <a class="underline" href={~p"/runs?trace_id=#{@trace_id}"}>open history</a>
            </div>
          </div>

          <div class="flex gap-3 text-sm">
            <a class="underline" href={~p"/runs"}>History</a>
          </div>
        </div>

        <div class="mt-6 grid grid-cols-1 lg:grid-cols-5 gap-4">
          <!-- Left: form -->
          <div class="lg:col-span-2 border border-slate-700 rounded-lg p-4 bg-slate-800">
            <form phx-submit="execute">
              <label class="block text-sm mb-1 text-slate-300">profile</label>
              <select
                name="profile_id"
                class="w-full px-3 py-2 rounded bg-slate-900 border border-slate-700"
              >
                <%= for p <- @profiles do %>
                  <option value={p.id} selected={@profile_id == p.id}>
                    <%= p.name || p.id %><%= if !p.enabled, do: " (disabled)", else: "" %>
                  </option>
                <% end %>
              </select>

              <div class="mt-3 grid grid-cols-2 gap-3">
                <div>
                  <label class="block text-sm mb-1 text-slate-300">trace_id (optional override)</label>
                  <input
                    name="trace_id"
                    value={@trace_id}
                    class="w-full px-3 py-2 rounded bg-slate-900 border border-slate-700"
                    placeholder="leave as-is to keep session trace"
                  />
                </div>
                <div>
                  <label class="block text-sm mb-1 text-slate-300">phase (optional)</label>
                  <select
                    name="phase"
                    class="w-full px-3 py-2 rounded bg-slate-900 border border-slate-700"
                  >
                    <option value="" selected={@phase == ""}>—</option>
                    <option value="draft" selected={@phase == "draft"}>draft</option>
                    <option value="critique" selected={@phase == "critique"}>critique</option>
                    <option value="revise" selected={@phase == "revise"}>revise</option>
                    <option value="final" selected={@phase == "final"}>final</option>
                  </select>
                </div>
              </div>

              <label class="block text-sm mt-3 mb-1 text-slate-300">prompt</label>
              <textarea
                name="prompt"
                rows="8"
                class="w-full px-3 py-2 rounded bg-slate-900 border border-slate-700 font-mono text-sm"
                placeholder="Type your prompt..."
              ><%= @prompt %></textarea>

              <button
                type="submit"
                class="mt-3 w-full px-3 py-2 rounded bg-indigo-600 hover:bg-indigo-500 disabled:opacity-50"
                disabled={@loading or @streaming}
              >
                <%= if @streaming, do: "Streaming…", else: if(@loading, do: "Executing…", else: "Execute") %>
              </button>
            </form>

            <%= if @error do %>
              <div class="mt-3 p-3 rounded border border-red-500/40 bg-red-950/30 text-sm">
                <div class="font-semibold">Error</div>
                <pre class="mt-2 whitespace-pre-wrap"><%= inspect(@error, pretty: true) %></pre>
              </div>
            <% end %>
          </div>

          <!-- Right: conversation -->
          <div class="lg:col-span-3 border border-slate-700 rounded-lg p-4 bg-slate-800">
            <h2 class="text-lg font-semibold">Conversation</h2>

            <div class="mt-3 space-y-3">
              <%= for m <- @messages do %>
                <div class={bubble_class(m["role"])}>
                  <div class="text-xs text-slate-400 mb-1"><%= m["role"] %></div>
                  <pre class="whitespace-pre-wrap"><%= m["content"] %></pre>
                </div>
              <% end %>

              <%= if @streaming do %>
                <div class="p-3 rounded border bg-slate-950 border-indigo-500/40 text-sm">
                  <div class="text-xs text-slate-400 mb-1">assistant (streaming)</div>
                  <pre class="whitespace-pre-wrap"><%= @stream_buffer %></pre>
                </div>
              <% end %>
            </div>

            <%= if @result do %>
              <div class="mt-4 grid grid-cols-1 md:grid-cols-2 gap-3 text-sm">
                <div class="p-3 rounded bg-slate-900 border border-slate-700">
                  <div class="text-slate-400">run_id</div>
                  <div class="font-mono break-all">
                    <%= if @result.run_id do %>
                      <a class="underline" href={~p"/api/runs/#{@result.run_id}"} target="_blank"><%= @result.run_id %></a>
                    <% else %>
                      <span class="text-slate-500">—</span>
                    <% end %>
                  </div>
                </div>

                <div class="p-3 rounded bg-slate-900 border border-slate-700">
                  <div class="text-slate-400">trace_id</div>
                  <div class="font-mono break-all">
                      <%= if @result.trace_id do %>
                        <a class="underline" href={~p"/runs?trace_id=#{@result.trace_id}"}><%= @result.trace_id %></a>
                      <% else %>
                        <span class="text-slate-500">—</span>
                      <% end %>

                  </div>
                </div>

                <div class="p-3 rounded bg-slate-900 border border-slate-700">
                  <div class="text-slate-400">status</div>
                  <div><%= @result.status %></div>
                </div>

                <div class="p-3 rounded bg-slate-900 border border-slate-700">
                  <div class="text-slate-400">latency</div>
                  <div><%= @result.latency_ms %> ms</div>
                </div>
              </div>

              <%= if @result.usage do %>
                <div class="mt-4 p-3 rounded bg-slate-900 border border-slate-700 text-sm">
                  <div class="font-semibold">Usage</div>
                  <pre class="mt-2 whitespace-pre-wrap"><%= inspect(@result.usage, pretty: true) %></pre>
                </div>
              <% end %>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
