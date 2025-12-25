defmodule AgentWebWeb.ChatExecuteLive do
  use AgentWebWeb, :live_view

  alias AgentRuntime.Llm.Executor
  alias AgentCore.Llm.Profiles
  alias AgentWeb.Llm.InputMapper

  @default_profile_id "req_llm"

  # 32-hex trace id (good enough for tracing; no extra deps)
  defp new_trace_id do
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
  end

  @impl true
  def mount(_params, _session, socket) do
    trace_id = new_trace_id()

    {:ok,
     socket
     |> assign(:profile_id, @default_profile_id)
     |> assign(:trace_id, trace_id)
     |> assign(:phase, "")
     |> assign(:prompt, "hi")
     |> assign(:messages, [])
     |> assign(:last_run_id, nil)
     |> assign(:loading, false)
     |> assign(:result, nil)
     |> assign(:error, nil)}
  end

  @impl true
  def handle_event("execute", %{"prompt" => prompt} = params, socket) do
    profile_id = Map.get(params, "profile_id", socket.assigns.profile_id)
    phase = Map.get(params, "phase", "")
    # If user provides trace_id in the input, use it; otherwise keep the session trace_id
    trace_id_param = Map.get(params, "trace_id", "") |> String.trim()
    trace_id = if trace_id_param == "", do: socket.assigns.trace_id, else: trace_id_param

    # Safe defaults (avoid KeyError if assigns change during refactors)
    messages0 = Map.get(socket.assigns, :messages, [])
    last_run_id = Map.get(socket.assigns, :last_run_id, nil)

    prompt = (prompt || "") |> String.trim()

    # Update UI state early
    socket =
      socket
      |> assign(:loading, true)
      |> assign(:error, nil)
      |> assign(:result, nil)
      |> assign(:profile_id, profile_id)
      |> assign(:phase, phase)
      |> assign(:trace_id, trace_id)

    # If empty prompt, do nothing (keep UI stable)
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

      exec_meta =
        %{"trace_id" => trace_id}
        |> maybe_put("parent_run_id", last_run_id)
        |> maybe_put("phase", blank_to_nil(phase))

      profile = Profiles.get!(profile_id)

      with {:ok, runtime_input} <- InputMapper.to_runtime(input),
           {:ok,
            %{response: resp, run_id: run_id, trace_id: tid, fingerprint: fp, latency_ms: latency}} <-
             Executor.execute(profile, %{}, runtime_input, exec_meta) do
        assistant_text = fetch_field(resp, [:output_text, "output_text"]) || ""

        messages =
          messages
          |> append_msg("assistant", assistant_text)

        result = %{
          status: "ok",
          output_text: assistant_text,
          usage: fetch_field(resp, [:usage, "usage"]),
          run_id: run_id,
          trace_id: tid,
          fingerprint: fp,
          latency_ms: latency
        }

        {:noreply,
         socket
         |> assign(:messages, messages)
         |> assign(:last_run_id, run_id)
         |> assign(:result, result)
         |> assign(:prompt, "")
         |> assign(:loading, false)}
      else
        {:error, reason} ->
          {:noreply, assign(socket, loading: false, error: normalize_error(reason))}

        other ->
          {:noreply, assign(socket, loading: false, error: normalize_error(other))}
      end
    end
  rescue
    _e in Ecto.NoResultsError ->
      {:noreply, assign(socket, loading: false, error: %{message: "profile_not_found"})}

    e ->
      {:noreply, assign(socket, loading: false, error: %{message: Exception.message(e)})}
  end

  # Store messages in OpenAI-compatible shape (maps with string keys)
  defp append_msg(messages, role, content) do
    content = (content || "") |> String.trim()

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

  defp fetch_field(map, keys) when is_map(map) do
    Enum.find_value(keys, fn k -> Map.get(map, k) end)
  end

  defp fetch_field(_other, _keys), do: nil

  defp normalize_error(%{__struct__: _} = s), do: %{message: inspect(s)}
  defp normalize_error({a, b}), do: %{message: inspect(a), detail: inspect(b)}
  defp normalize_error(other), do: %{message: inspect(other)}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen p-6 bg-slate-900 text-slate-100">
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
              <label class="block text-sm mb-1 text-slate-300">profile_id</label>
              <input
                name="profile_id"
                value={@profile_id}
                class="w-full px-3 py-2 rounded bg-slate-900 border border-slate-700"
                placeholder="req_llm"
              />

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
                disabled={@loading}
              >
                <%= if @loading, do: "Executing…", else: "Execute" %>
              </button>
            </form>

            <%= if @error do %>
              <div class="mt-3 p-3 rounded border border-red-500/40 bg-red-950/30 text-sm">
                <div class="font-semibold">Error</div>
                <pre class="mt-2 whitespace-pre-wrap"><%= inspect(@error, pretty: true) %></pre>
              </div>
            <% end %>
          </div>

          <!-- Right: output -->
          <div class="lg:col-span-3 border border-slate-700 rounded-lg p-4 bg-slate-800">
            <h2 class="text-lg font-semibold">Response</h2>

            <%= if @result do %>
              <div class="mt-3 p-3 rounded bg-slate-900 border border-slate-700">
                <pre class="whitespace-pre-wrap text-sm"><%= @result.output_text %></pre>
              </div>

              <div class="mt-4 grid grid-cols-1 md:grid-cols-2 gap-3 text-sm">
                <div class="p-3 rounded bg-slate-900 border border-slate-700">
                  <div class="text-slate-400">run_id</div>
                  <div class="font-mono break-all">
                    <a class="underline" href={~p"/api/runs/#{@result.run_id}"} target="_blank"><%= @result.run_id %></a>
                  </div>
                </div>

                <div class="p-3 rounded bg-slate-900 border border-slate-700">
                  <div class="text-slate-400">trace_id</div>
                  <div class="font-mono break-all">
                    <a class="underline" href={~p"/runs?trace_id=#{@result.trace_id}"}><%= @result.trace_id %></a>
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
            <% else %>
              <div class="mt-3 text-slate-400 text-sm">
                Execute a prompt to see the response and run metadata.
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
