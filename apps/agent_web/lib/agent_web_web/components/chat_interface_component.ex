defmodule AgentWebWeb.ChatInterfaceComponent do
  use AgentWebWeb, :live_component
  import AgentWebWeb.MessagesComponent

  @impl true
  def render(assigns) do
    ~H"""
    <div class="card bg-base-200 shadow-xl">
      <div class="card-body">
        <div class="flex items-center justify-between mb-4">
          <h2 class="card-title">Chat Interface</h2>

          <%= if @selected_agent do %>
            <div class="badge badge-primary badge-outline">
              Agent: {@selected_agent.name || @selected_agent.id}
            </div>
          <% end %>
        </div>
        <!-- Chat Messages Container -->
        <div class="bg-base-100 rounded-lg border border-base-300 h-96 flex flex-col">
          <!-- Messages Display -->
          <div class="flex-1 overflow-y-auto p-4">
            <%= if @messages == [] do %>
              <div class="text-center text-base-content/50 mt-8">
                <div class="text-lg font-semibold mb-2">Start Testing</div>

                <div class="text-sm">Send a message to begin testing the selected agent</div>
              </div>
            <% else %>
              <.messages
                messages={@messages}
                streaming={@streaming}
                stream_buffer={@stream_buffer}
                conversation_id={@conversation_id}
              />
            <% end %>
          </div>
          <!-- Workflow Progress Indicator -->
          <%= if @execution_status && @execution_status.status != :idle do %>
            <div class="border-t border-base-300 px-4 py-2 bg-base-50">
              <div class="flex items-center gap-2 text-sm">
                <div class="loading loading-spinner loading-xs"></div>

                <span class="text-base-content/70">
                  Workflow: {@execution_status.current_step_name || "Processing..."} ({@execution_status.completed_steps}/{@execution_status.total_steps} steps)
                </span>
              </div>
            </div>
          <% end %>
          <!-- Message Input -->
          <div class="border-t border-base-300 p-4">
            <form phx-submit="send_message" phx-target={@myself} class="flex gap-2">
              <input
                type="text"
                name="message"
                placeholder="Type your test message..."
                class="input input-bordered flex-1"
                disabled={@streaming || !@selected_agent}
                value={@current_input}
              />
              <button
                type="submit"
                class="btn btn-primary"
                disabled={@streaming || !@selected_agent}
              >
                {if @streaming, do: "Sending...", else: "Send"}
              </button>
            </form>
            <!-- Error Display -->
            <%= if @error do %>
              <div class="alert alert-error mt-2">
                <div class="flex items-start gap-2">
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    class="stroke-current shrink-0 h-6 w-6"
                    fill="none"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z"
                    />
                  </svg>
                  <div>
                    <h3 class="font-bold">Agent Error</h3>

                    <div class="text-sm">{@error}</div>
                  </div>
                </div>

                <div class="flex-none">
                  <button class="btn btn-sm btn-ghost" phx-click="clear_error" phx-target={@myself}>
                    Retry
                  </button>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:messages, [])
     |> assign(:streaming, false)
     |> assign(:stream_buffer, "")
     |> assign(:conversation_id, nil)
     |> assign(:conversation_context, %{})
     |> assign(:current_input, "")
     |> assign(:error, nil)}
  end

  @impl true
  def update(%{action: :add_assistant_message, content: content, metadata: metadata}, socket) do
    assistant_message = create_assistant_message(content, metadata)

    socket =
      socket
      |> update(:messages, &(&1 ++ [assistant_message]))
      |> assign(:streaming, false)
      |> assign(:stream_buffer, "")

    {:ok, socket}
  end

  def update(%{action: :set_error, error: error_message}, socket) do
    socket =
      socket
      |> assign(:error, error_message)
      |> assign(:streaming, false)

    {:ok, socket}
  end

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> maybe_initialize_conversation()}
  end

  @impl true
  def handle_event("send_message", %{"message" => message}, socket) do
    if String.trim(message) != "" do
      # Add user message to chat with conversation context
      user_message = create_user_message(message, socket.assigns.selected_agent)

      # Update conversation context
      updated_context =
        update_conversation_context(socket.assigns.conversation_context, message, :user)

      socket =
        socket
        |> update(:messages, &(&1 ++ [user_message]))
        |> assign(:current_input, "")
        |> assign(:streaming, true)
        |> assign(:error, nil)
        |> assign(:conversation_context, updated_context)

      # Send message to parent LiveView for processing with context
      send(self(), {:chat_send_message, message, socket.assigns.conversation_id, updated_context})

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("clear_error", _params, socket) do
    {:noreply, assign(socket, :error, nil)}
  end

  # Public functions for parent LiveView to call

  def add_assistant_message(socket, content, metadata \\ %{}) do
    assistant_message = create_assistant_message(content, metadata)

    socket
    |> update(:messages, &(&1 ++ [assistant_message]))
    |> assign(:streaming, false)
    |> assign(:stream_buffer, "")
  end

  def update_streaming_content(socket, content) do
    socket
    |> assign(:stream_buffer, content)
    |> assign(:streaming, true)
  end

  def set_error(socket, error_message) do
    socket
    |> assign(:error, error_message)
    |> assign(:streaming, false)
  end

  def clear_messages(socket) do
    socket
    |> assign(:messages, [])
    |> assign(:streaming, false)
    |> assign(:stream_buffer, "")
    |> assign(:error, nil)
  end

  # Private helper functions

  defp maybe_initialize_conversation(socket) do
    if socket.assigns[:selected_agent] && !socket.assigns[:conversation_id] do
      conversation_id = generate_conversation_id(socket.assigns.selected_agent)
      assign(socket, :conversation_id, conversation_id)
    else
      socket
    end
  end

  defp generate_conversation_id(agent) do
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    "chat_#{agent.id}_#{timestamp}"
  end

  defp create_user_message(content, agent) do
    %{
      "id" => generate_message_id(),
      "role" => "user",
      "content" => content,
      "timestamp" => format_timestamp(DateTime.utc_now()),
      "agent_id" => agent && agent.id,
      "agent_name" => agent && (agent.name || agent.id)
    }
  end

  defp update_conversation_context(context, message, role) do
    context
    |> Map.put(:last_message, %{content: message, role: role, timestamp: DateTime.utc_now()})
    |> Map.update(:message_count, 1, &(&1 + 1))
    |> Map.update(:user_messages, [], fn messages ->
      if role == :user do
        # Keep last 5 user messages
        [message | messages] |> Enum.take(5)
      else
        messages
      end
    end)
  end

  defp create_assistant_message(content, metadata) do
    %{
      "id" => generate_message_id(),
      "role" => "assistant",
      "content" => content,
      "timestamp" => format_timestamp(DateTime.utc_now()),
      "workflow_id" => Map.get(metadata, :workflow_id),
      "execution_time_ms" => Map.get(metadata, :execution_time_ms),
      "token_count" => Map.get(metadata, :token_count)
    }
  end

  defp generate_message_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp format_timestamp(datetime) do
    datetime
    |> DateTime.truncate(:second)
    |> DateTime.to_string()
    |> String.replace("Z", " UTC")
  end
end
