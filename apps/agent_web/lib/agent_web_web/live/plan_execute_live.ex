defmodule AgentWebWeb.PlanExecuteLive do
  use AgentWebWeb, :live_view
  alias AgentWeb.Llm.ProfileStoreEcto

  @default_profile_id "req_llm"
  @stream_endpoint "/api/plans/execute/stream"


  @impl true
  def mount(%{"conversation_id" => conversation_id}, _session, socket) do
    with {:ok, _} <- Ecto.UUID.cast(conversation_id) do
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
       |> assign(:conversation_id, conversation_id)
       |> assign(:profiles, profiles)
       |> assign(:profile_id, selected_profile_id)
       |> assign(:trace_id, Ecto.UUID.generate()) # internal, not shown
       |> assign(:prompt, "")
       |> assign(:messages, [])
       |> assign(:last_run_id, nil)
       |> assign(:loading, false)
       |> assign(:result, nil)
       |> assign(:error, nil)
       |> assign(:streaming, false)
       |> assign(:stream_buffer, "")
       |> assign(:conversations, [%{id: conversation_id, name: nil}])}

    else
      :error ->
        {:ok,
         socket
         |> put_flash(:error, "Invalid conversation id")
         |> push_navigate(to: "/")}
    end
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
        messages = messages0 |> append_msg("user", prompt)

        input = %{
          "type" => "chat",
          "messages" => messages
        }

        payload =
          %{
            "profile_id" => profile_id,
            "input" => input,
            "overrides" => %{},
            "conversation_id" => socket.assigns.conversation_id
          }
          |> maybe_put("parent_run_id", last_run_id)


        {:noreply,
         socket
         |> assign(:messages, messages)
         |> assign(:streaming, true)
         |> assign(:stream_buffer, "")
         |> assign(:prompt, "")
         |> assign(:loading, false)
         |> push_event("sse_start", %{
           url: @stream_endpoint,  # ΑΛΛΑΓΗ: Χρήση module attribute
           payload: payload
         })}
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
    # 1) Flat: %{"run_id" => "...", "trace_id" => "...", ...}
    # 2) Nested: %{"meta" => %{...}}
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

  # NEW: Handle clarification requests from PlanExecutor
  @impl true
  def handle_event("sse_clarify", %{"question" => question, "trace_id" => trace_id}, socket) do
    messages =
      socket.assigns.messages
      |> append_msg("system", "❓ Clarification needed: #{question}")

    {:noreply,
     socket
     |> assign(:messages, messages)
     |> assign(:streaming, false)
     |> assign(:stream_buffer, "")
     |> assign(:trace_id, trace_id)
     |> assign(:loading, false)
     |> assign(:result, %{
       status: "needs_clarification",
       question: question,
       trace_id: trace_id
     })}
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

  @impl true
  def handle_event("new_conversation", _params, socket) do
    new_id = Ecto.UUID.generate()
    {:noreply, push_navigate(socket, to: "/chat/#{new_id}/plan")}
  end


  @impl true
  def handle_event("clear_messages", _params, socket) do
    {:noreply,
    socket
    |> assign(:messages, [])
    |> assign(:result, nil)
    |> assign(:error, nil)
    |> assign(:stream_buffer, "")
    |> assign(:streaming, false)}
  end

  # --- helpers ---

  defp append_msg(messages, role, content) do
    content = (content || "") |> to_string() |> String.trim()

    if content == "" do
      messages
    else
      # messages ++ [%{"role" => role, "content" => content}]
      messages ++ [%{"role" => role, "content" => content}]
    end
  end

  defp maybe_put(map, _k, nil), do: map
  defp maybe_put(map, _k, ""), do: map
  defp maybe_put(map, k, v), do: Map.put(map, k, v)

  # defp blank_to_nil(""), do: nil
  # defp blank_to_nil(nil), do: nil
  # defp blank_to_nil(v), do: v

  defp bubble_class("user"), do: "p-4 rounded-xl bg-slate-800 border border-slate-700"

  defp bubble_class("assistant"),
    do: "p-4 rounded-xl bg-gradient-to-br from-slate-800 to-slate-900 border border-slate-700"

  defp bubble_class("system"), do: "p-4 rounded-xl bg-blue-900/20 border border-blue-800/40"
  defp bubble_class(_), do: "p-4 rounded-xl bg-slate-800 border border-slate-700"

  defp role_icon("user"), do: "👤"
  defp role_icon("assistant"), do: "🤖"
  defp role_icon("system"), do: "⚙️"
  defp role_icon(_), do: "💬"

  defp role_icon_class("user"),
    do: "w-8 h-8 rounded-full bg-blue-600 flex items-center justify-center"

  defp role_icon_class("assistant"),
    do:
      "w-8 h-8 rounded-full bg-gradient-to-r from-indigo-500 to-purple-500 flex items-center justify-center"

  defp role_icon_class("system"),
    do: "w-8 h-8 rounded-full bg-cyan-600 flex items-center justify-center"

  defp role_icon_class(_),
    do: "w-8 h-8 rounded-full bg-slate-700 flex items-center justify-center"

  defp status_badge_class("completed"),
    do: "px-3 py-1 text-xs rounded-full bg-green-900/30 text-green-400"

  defp status_badge_class("failed"),
    do: "px-3 py-1 text-xs rounded-full bg-red-900/30 text-red-400"

  defp status_badge_class("running"),
    do: "px-3 py-1 text-xs rounded-full bg-yellow-900/30 text-yellow-400"

  defp status_badge_class(_), do: "px-3 py-1 text-xs rounded-full bg-slate-700 text-slate-300"


end
