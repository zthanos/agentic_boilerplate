defmodule AgentWebWeb.AdminChatLive do
  @moduledoc """
  Admin chat management LiveView for monitoring and managing chat sessions.
  Provides interface for viewing active sessions, chat history, and user interactions.
  """
  use AgentWebWeb, :live_view
  alias AgentWebWeb.AdminLayouts

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to chat-related events
      Phoenix.PubSub.subscribe(AgentWeb.PubSub, "admin:chat")
      Phoenix.PubSub.subscribe(AgentWeb.PubSub, "chat:sessions")
      # Refresh active sessions periodically
      :timer.send_interval(10_000, self(), :refresh_sessions)
      # Refresh system processes periodically
      :timer.send_interval(15_000, self(), :refresh_processes)
    end

    {:ok,
     socket
     |> assign(:current_page, :chat)
     |> assign(:current_section, :operations)
     |> assign(:page_title, "Chat Management")
     |> assign(:sidebar_collapsed, false)
     |> assign(:selected_session, nil)
     |> assign(:view_mode, :overview)
     |> load_chat_data()
     |> load_system_processes()}
  end

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def handle_event("toggle_sidebar", _params, socket) do
    new_state = !socket.assigns.sidebar_collapsed
    {:noreply, assign(socket, :sidebar_collapsed, new_state)}
  end

  # 2. Handler για το JavaScript hook persistence (optional)
  @impl true
  def handle_event("set_sidebar_state", %{"collapsed" => collapsed}, socket) do
    {:noreply, assign(socket, :sidebar_collapsed, collapsed)}
  end

  # 3. Handler για το μήνυμα από το LiveComponent
  #    Αυτό είναι το ΚΡΙΣΙΜΟ κομμάτι!
  @impl true
  def handle_info({:toggle_sidebar}, socket) do
    new_state = !socket.assigns.sidebar_collapsed
    {:noreply, assign(socket, :sidebar_collapsed, new_state)}
  end

  @impl true
  def handle_event("select_session", %{"session_id" => session_id}, socket) do
    session = Enum.find(socket.assigns.active_sessions, &(&1.id == session_id))

    {:noreply,
     socket
     |> assign(:selected_session, session)
     |> assign(:view_mode, :session_detail)
     |> load_session_messages(session_id)}
  end

  @impl true
  def handle_event("view_overview", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_session, nil)
     |> assign(:view_mode, :overview)}
  end

  @impl true
  def handle_event("terminate_session", %{"session_id" => session_id}, socket) do
    # TODO: Implement session termination
    # AgentWebWeb.AdminPubSub.broadcast_session_terminated(session_id)
    {:noreply, put_flash(socket, :info, "Session #{session_id} terminated")}
  end

  @impl true
  def handle_event("pause_session", %{"session_id" => session_id}, socket) do
    # TODO: Implement session pausing
    {:noreply, put_flash(socket, :info, "Session #{session_id} paused")}
  end

  @impl true
  def handle_event("resume_session", %{"session_id" => session_id}, socket) do
    # TODO: Implement session resuming
    {:noreply, put_flash(socket, :info, "Session #{session_id} resumed")}
  end

  @impl true
  def handle_event("view_system_processes", _params, socket) do
    {:noreply, assign(socket, :view_mode, :system_processes)}
  end

  @impl true
  def handle_event("kill_process", %{"process_id" => process_id}, socket) do
    # TODO: Implement process termination with safety checks
    {:noreply, put_flash(socket, :warning, "Process #{process_id} terminated")}
  end

  @impl true
  def handle_event("restart_service", %{"service" => service}, socket) do
    # TODO: Implement service restart
    {:noreply, put_flash(socket, :info, "Service #{service} restarted")}
  end

  @impl true
  def handle_event("export_chat", %{"session_id" => session_id}, socket) do
    # TODO: Implement chat export
    {:noreply, put_flash(socket, :info, "Exporting chat #{session_id}")}
  end

  @impl true
  def handle_info({:toggle_sidebar}, socket) do
    {:noreply, assign(socket, :sidebar_collapsed, !socket.assigns.sidebar_collapsed)}
  end

  @impl true
  def handle_info({:close_mobile_sidebar}, socket) do
    {:noreply, assign(socket, :sidebar_collapsed, true)}
  end

  @impl true
  def handle_info(:refresh_sessions, socket) do
    {:noreply, load_chat_data(socket)}
  end

  @impl true
  def handle_info(:refresh_processes, socket) do
    {:noreply, load_system_processes(socket)}
  end

  @impl true
  def handle_info({:session_started, session}, socket) do
    updated_sessions = [session | socket.assigns.active_sessions]
    {:noreply, assign(socket, :active_sessions, updated_sessions)}
  end

  @impl true
  def handle_info({:session_ended, session_id}, socket) do
    updated_sessions = Enum.reject(socket.assigns.active_sessions, &(&1.id == session_id))
    {:noreply, assign(socket, :active_sessions, updated_sessions)}
  end

  @impl true
  def handle_info({:new_message, session_id, _message}, socket) do
    # Update session with new message indicator
    updated_sessions =
      Enum.map(socket.assigns.active_sessions, fn session ->
        if session.id == session_id do
          Map.update(session, :message_count, 1, &(&1 + 1))
        else
          session
        end
      end)

    {:noreply, assign(socket, :active_sessions, updated_sessions)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AdminLayouts.admin
      flash={@flash}
      current_page={@current_page}
      current_section={@current_section}
      sidebar_collapsed={@sidebar_collapsed}
    >
      <!-- Header -->
      <div class="mb-8">
        <.header>
          Chat Management
          <:subtitle>
            Monitor active chat sessions and manage user interactions
            <span class="inline-flex items-center gap-1 ml-2">
              <div class="w-2 h-2 bg-success rounded-full animate-pulse"></div>
              <span class="text-xs text-success">Live</span>
            </span>
          </:subtitle>

          <:actions>
            <div class="flex gap-2">
              <button
                class={[
                  "btn btn-sm",
                  @view_mode == :overview && "btn-primary",
                  @view_mode != :overview && "btn-outline"
                ]}
                phx-click="view_overview"
              >
                <.icon name="hero-chat-bubble-left-right" class="size-4 mr-2" /> Chat Overview
              </button>
              <button
                class={[
                  "btn btn-sm",
                  @view_mode == :system_processes && "btn-primary",
                  @view_mode != :system_processes && "btn-outline"
                ]}
                phx-click="view_system_processes"
              >
                <.icon name="hero-cog-6-tooth" class="size-4 mr-2" /> System Processes
              </button>
              <button
                :if={@view_mode == :session_detail}
                class="btn btn-outline btn-sm"
                phx-click="view_overview"
              >
                <.icon name="hero-arrow-left" class="size-4 mr-2" /> Back
              </button>
            </div>
          </:actions>
        </.header>
      </div>

      <div :if={@view_mode == :overview}>
        <!-- Chat Overview -->
        <.chat_overview
          active_sessions={@active_sessions}
          chat_stats={@chat_stats}
          recent_conversations={@recent_conversations}
        />
      </div>

      <div :if={@view_mode == :session_detail && @selected_session}>
        <!-- Session Detail View -->
        <.session_detail
          session={@selected_session}
          messages={@session_messages}
        />
      </div>

      <div :if={@view_mode == :system_processes}>
        <!-- System Processes View -->
        <.system_processes
          processes={@system_processes}
          services={@system_services}
          system_stats={@system_stats}
        />
      </div>
    </AdminLayouts.admin>
    """
  end

  # Load chat data including active sessions and statistics
  defp load_chat_data(socket) do
    # TODO: Integrate with actual chat system
    active_sessions = get_mock_active_sessions()
    chat_stats = calculate_chat_stats(active_sessions)
    recent_conversations = get_mock_recent_conversations()

    socket
    |> assign(:active_sessions, active_sessions)
    |> assign(:chat_stats, chat_stats)
    |> assign(:recent_conversations, recent_conversations)
  end

  # Load system processes and services data
  defp load_system_processes(socket) do
    # TODO: Integrate with actual system monitoring
    processes = get_mock_system_processes()
    services = get_mock_system_services()
    system_stats = calculate_system_stats(processes, services)

    socket
    |> assign(:system_processes, processes)
    |> assign(:system_services, services)
    |> assign(:system_stats, system_stats)
  end

  defp load_session_messages(socket, session_id) do
    # TODO: Load actual messages for the session
    messages = get_mock_session_messages(session_id)
    assign(socket, :session_messages, messages)
  end

  # Mock data functions - replace with actual integrations
  defp get_mock_active_sessions do
    [
      %{
        id: "session_abc123",
        user: "john.doe@example.com",
        agent: "ChatBot-v2",
        started_at: "14:30:15",
        duration: "5m 23s",
        message_count: 12,
        status: "active",
        last_activity: "30s ago"
      },
      %{
        id: "session_def456",
        user: "jane.smith@example.com",
        agent: "Assistant-Pro",
        started_at: "14:25:42",
        duration: "8m 45s",
        message_count: 18,
        status: "active",
        last_activity: "1m ago"
      },
      %{
        id: "session_ghi789",
        user: "admin@example.com",
        agent: "DataAnalyzer",
        started_at: "14:20:10",
        duration: "15m 12s",
        message_count: 25,
        status: "idle",
        last_activity: "5m ago"
      }
    ]
  end

  defp calculate_chat_stats(sessions) do
    %{
      total_active: length(sessions),
      total_messages: Enum.sum(Enum.map(sessions, & &1.message_count)),
      avg_duration: "8m 30s",
      active_agents: sessions |> Enum.map(& &1.agent) |> Enum.uniq() |> length()
    }
  end

  defp get_mock_recent_conversations do
    [
      %{
        id: "conv_123",
        user: "user123",
        agent: "ChatBot-v2",
        last_message: "Thank you for your help!",
        ended_at: "2 hours ago",
        duration: "12m 34s",
        message_count: 15
      },
      %{
        id: "conv_456",
        user: "user456",
        agent: "Assistant-Pro",
        last_message: "That solved my problem perfectly.",
        ended_at: "3 hours ago",
        duration: "8m 12s",
        message_count: 9
      },
      %{
        id: "conv_789",
        user: "user789",
        agent: "DataAnalyzer",
        last_message: "The analysis looks comprehensive.",
        ended_at: "4 hours ago",
        duration: "25m 45s",
        message_count: 32
      }
    ]
  end

  defp get_mock_session_messages(_session_id) do
    [
      %{
        id: "msg_1",
        role: "user",
        content: "Hello, I need help with my account settings.",
        timestamp: "14:30:15"
      },
      %{
        id: "msg_2",
        role: "assistant",
        content:
          "I'd be happy to help you with your account settings. What specific aspect would you like to modify?",
        timestamp: "14:30:18"
      },
      %{
        id: "msg_3",
        role: "user",
        content: "I want to change my notification preferences.",
        timestamp: "14:30:45"
      },
      %{
        id: "msg_4",
        role: "assistant",
        content:
          "I can guide you through updating your notification preferences. Let me walk you through the steps...",
        timestamp: "14:30:48"
      }
    ]
  end

  defp get_mock_system_processes do
    [
      %{
        id: "proc_001",
        name: "AgentWeb.Endpoint",
        pid: "0.123.0",
        status: "running",
        cpu_usage: "2.3%",
        memory_usage: "45.2 MB",
        uptime: "2h 15m",
        type: "web_server"
      },
      %{
        id: "proc_002",
        name: "AgentCore.Supervisor",
        pid: "0.124.0",
        status: "running",
        cpu_usage: "1.8%",
        memory_usage: "32.1 MB",
        uptime: "2h 15m",
        type: "supervisor"
      },
      %{
        id: "proc_003",
        name: "Phoenix.PubSub",
        pid: "0.125.0",
        status: "running",
        cpu_usage: "0.5%",
        memory_usage: "12.8 MB",
        uptime: "2h 15m",
        type: "pubsub"
      },
      %{
        id: "proc_004",
        name: "Ecto.Repo.Pool",
        pid: "0.126.0",
        status: "running",
        cpu_usage: "0.8%",
        memory_usage: "28.4 MB",
        uptime: "2h 15m",
        type: "database"
      },
      %{
        id: "proc_005",
        name: "Task.Supervisor",
        pid: "0.127.0",
        status: "idle",
        cpu_usage: "0.1%",
        memory_usage: "8.2 MB",
        uptime: "2h 15m",
        type: "task_supervisor"
      }
    ]
  end

  defp get_mock_system_services do
    [
      %{
        name: "Phoenix Server",
        status: "running",
        port: 4000,
        health: "healthy",
        last_restart: "2h 15m ago",
        auto_restart: true
      },
      %{
        name: "Database Connection",
        status: "running",
        port: 5432,
        health: "healthy",
        last_restart: "2h 15m ago",
        auto_restart: true
      },
      %{
        name: "PubSub System",
        status: "running",
        port: nil,
        health: "healthy",
        last_restart: "2h 15m ago",
        auto_restart: true
      },
      %{
        name: "Agent Runtime",
        status: "running",
        port: nil,
        health: "warning",
        last_restart: "45m ago",
        auto_restart: true
      }
    ]
  end

  defp calculate_system_stats(processes, services) do
    running_processes = Enum.count(processes, &(&1.status == "running"))
    healthy_services = Enum.count(services, &(&1.health == "healthy"))

    total_memory =
      processes
      |> Enum.map(fn proc ->
        proc.memory_usage
        |> String.replace(" MB", "")
        |> Float.parse()
        |> elem(0)
      end)
      |> Enum.sum()

    %{
      running_processes: running_processes,
      total_processes: length(processes),
      healthy_services: healthy_services,
      total_services: length(services),
      total_memory_mb: Float.round(total_memory, 1),
      system_uptime: "2h 15m"
    }
  end

  # Component for chat overview
  attr :active_sessions, :list, required: true
  attr :chat_stats, :map, required: true
  attr :recent_conversations, :list, required: true

  defp chat_overview(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Chat Statistics -->
      <div class="grid grid-cols-1 md:grid-cols-4 gap-4">
        <.stat_card
          title="Active Sessions"
          value={@chat_stats.total_active}
          icon="hero-chat-bubble-left-right"
          color="primary"
        />
        <.stat_card
          title="Total Messages"
          value={@chat_stats.total_messages}
          icon="hero-chat-bubble-oval-left"
          color="secondary"
        />
        <.stat_card
          title="Avg Duration"
          value={@chat_stats.avg_duration}
          icon="hero-clock"
          color="accent"
        />
        <.stat_card
          title="Active Agents"
          value={@chat_stats.active_agents}
          icon="hero-cpu-chip"
          color="info"
        />
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <!-- Active Sessions -->
        <div class="card bg-base-200 shadow-sm">
          <div class="card-body">
            <h3 class="card-title text-lg">Active Sessions</h3>

            <div class="space-y-3">
              <.session_card
                :for={session <- @active_sessions}
                session={session}
              />
            </div>
          </div>
        </div>
        <!-- Recent Conversations -->
        <div class="card bg-base-200 shadow-sm">
          <div class="card-body">
            <h3 class="card-title text-lg">Recent Conversations</h3>

            <div class="space-y-3">
              <.conversation_card
                :for={conversation <- @recent_conversations}
                conversation={conversation}
              />
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Component for session detail view
  attr :session, :map, required: true
  attr :messages, :list, required: true

  defp session_detail(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Session Info -->
      <div class="card bg-base-200 shadow-sm">
        <div class="card-body">
          <div class="flex justify-between items-start">
            <div>
              <h3 class="text-lg font-semibold">Session Details</h3>

              <div class="grid grid-cols-2 md:grid-cols-4 gap-4 mt-4">
                <div>
                  <p class="text-sm text-base-content/70">User</p>

                  <p class="font-medium">{@session.user}</p>
                </div>

                <div>
                  <p class="text-sm text-base-content/70">Agent</p>

                  <p class="font-medium">{@session.agent}</p>
                </div>

                <div>
                  <p class="text-sm text-base-content/70">Duration</p>

                  <p class="font-medium">{@session.duration}</p>
                </div>

                <div>
                  <p class="text-sm text-base-content/70">Messages</p>

                  <p class="font-medium">{@session.message_count}</p>
                </div>
              </div>
            </div>

            <div class="flex gap-2">
              <button
                class="btn btn-outline btn-sm"
                phx-click="export_chat"
                phx-value-session_id={@session.id}
              >
                <.icon name="hero-arrow-down-tray" class="size-4" />
              </button>
              <button
                class="btn btn-error btn-sm"
                phx-click="terminate_session"
                phx-value-session_id={@session.id}
              >
                <.icon name="hero-x-mark" class="size-4" />
              </button>
            </div>
          </div>
        </div>
      </div>
      <!-- Chat Messages -->
      <div class="card bg-base-200 shadow-sm">
        <div class="card-body">
          <h3 class="card-title text-lg mb-4">Conversation</h3>

          <div class="space-y-4 max-h-96 overflow-y-auto">
            <.message_bubble
              :for={message <- @messages}
              message={message}
            />
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Component for system processes view
  attr :processes, :list, required: true
  attr :services, :list, required: true
  attr :system_stats, :map, required: true

  defp system_processes(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- System Statistics -->
      <div class="grid grid-cols-1 md:grid-cols-4 gap-4">
        <.stat_card
          title="Running Processes"
          value={"#{@system_stats.running_processes}/#{@system_stats.total_processes}"}
          icon="hero-cpu-chip"
          color="primary"
        />
        <.stat_card
          title="Healthy Services"
          value={"#{@system_stats.healthy_services}/#{@system_stats.total_services}"}
          icon="hero-server"
          color="success"
        />
        <.stat_card
          title="Memory Usage"
          value={"#{@system_stats.total_memory_mb} MB"}
          icon="hero-circle-stack"
          color="warning"
        />
        <.stat_card
          title="System Uptime"
          value={@system_stats.system_uptime}
          icon="hero-clock"
          color="info"
        />
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <!-- System Processes -->
        <div class="card bg-base-200 shadow-sm">
          <div class="card-body">
            <h3 class="card-title text-lg">System Processes</h3>

            <div class="overflow-x-auto">
              <table class="table table-sm">
                <thead>
                  <tr>
                    <th>Process</th>

                    <th>Status</th>

                    <th>CPU</th>

                    <th>Memory</th>

                    <th>Actions</th>
                  </tr>
                </thead>

                <tbody>
                  <tr :for={process <- @processes}>
                    <td>
                      <div>
                        <div class="font-medium text-sm">{process.name}</div>

                        <div class="text-xs text-base-content/70">PID: {process.pid}</div>
                      </div>
                    </td>

                    <td><.process_status_badge status={process.status} /></td>

                    <td class="text-sm">{process.cpu_usage}</td>

                    <td class="text-sm">{process.memory_usage}</td>

                    <td>
                      <div class="flex gap-1">
                        <button
                          class="btn btn-ghost btn-xs"
                          title="View Details"
                        >
                          <.icon name="hero-eye" class="size-3" />
                        </button>
                        <button
                          class="btn btn-error btn-xs"
                          phx-click="kill_process"
                          phx-value-process_id={process.id}
                          title="Terminate Process"
                        >
                          <.icon name="hero-x-mark" class="size-3" />
                        </button>
                      </div>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </div>
        <!-- System Services -->
        <div class="card bg-base-200 shadow-sm">
          <div class="card-body">
            <h3 class="card-title text-lg">System Services</h3>

            <div class="space-y-3">
              <.service_card
                :for={service <- @services}
                service={service}
              />
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Helper components
  attr :title, :string, required: true
  attr :value, :any, required: true
  attr :icon, :string, required: true
  attr :color, :string, required: true

  defp stat_card(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-sm">
      <div class="card-body p-4">
        <div class="flex items-center gap-3">
          <div class={["p-2 rounded-lg", "bg-#{@color}/10"]}>
            <.icon name={@icon} class={"size-5 text-#{@color}"} />
          </div>

          <div>
            <p class="text-2xl font-bold">{@value}</p>

            <p class="text-sm text-base-content/70">{@title}</p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :session, :map, required: true

  defp session_card(assigns) do
    ~H"""
    <div
      class="p-3 bg-base-100 rounded-lg hover:bg-base-300 transition-colors cursor-pointer"
      phx-click="select_session"
      phx-value-session_id={@session.id}
    >
      <div class="flex justify-between items-start">
        <div class="flex-1">
          <div class="flex items-center gap-2">
            <.icon name="hero-user" class="size-4 text-primary" />
            <span class="font-medium">{@session.user}</span>
            <.session_status_badge status={@session.status} />
          </div>

          <p class="text-sm text-base-content/70 mt-1">
            Agent: {@session.agent} • {@session.message_count} messages
          </p>

          <p class="text-xs text-base-content/50">
            Started: {@session.started_at} • Last activity: {@session.last_activity}
          </p>
        </div>

        <div class="text-right">
          <p class="text-sm font-medium">{@session.duration}</p>
        </div>
      </div>
    </div>
    """
  end

  attr :conversation, :map, required: true

  defp conversation_card(assigns) do
    ~H"""
    <div class="p-3 bg-base-100 rounded-lg">
      <div class="flex justify-between items-start">
        <div class="flex-1">
          <div class="flex items-center gap-2">
            <.icon name="hero-user" class="size-4 text-base-content/70" />
            <span class="font-medium">{@conversation.user}</span>
          </div>

          <p class="text-sm text-base-content/70 mt-1">"{@conversation.last_message}"</p>

          <p class="text-xs text-base-content/50">
            {@conversation.agent} • {@conversation.message_count} messages • {@conversation.ended_at}
          </p>
        </div>
      </div>
    </div>
    """
  end

  attr :status, :string, required: true

  defp session_status_badge(assigns) do
    {badge_class, icon} =
      case assigns.status do
        "active" -> {"badge-success", "hero-bolt"}
        "idle" -> {"badge-warning", "hero-pause"}
        _ -> {"badge-ghost", "hero-question-mark-circle"}
      end

    assigns = assign(assigns, :badge_class, badge_class)
    assigns = assign(assigns, :icon, icon)

    ~H"""
    <div class={["badge badge-xs gap-1", @badge_class]}>
      <.icon name={@icon} class="size-2" /> {String.capitalize(@status)}
    </div>
    """
  end

  attr :status, :string, required: true

  defp process_status_badge(assigns) do
    {badge_class, icon} =
      case assigns.status do
        "running" -> {"badge-success", "hero-play"}
        "idle" -> {"badge-warning", "hero-pause"}
        "stopped" -> {"badge-error", "hero-stop"}
        _ -> {"badge-ghost", "hero-question-mark-circle"}
      end

    assigns = assign(assigns, :badge_class, badge_class)
    assigns = assign(assigns, :icon, icon)

    ~H"""
    <div class={["badge badge-xs gap-1", @badge_class]}>
      <.icon name={@icon} class="size-2" /> {String.capitalize(@status)}
    </div>
    """
  end

  attr :service, :map, required: true

  defp service_card(assigns) do
    ~H"""
    <div class="p-3 bg-base-100 rounded-lg">
      <div class="flex justify-between items-start">
        <div class="flex-1">
          <div class="flex items-center gap-2">
            <.icon name="hero-server" class="size-4 text-primary" />
            <span class="font-medium">{@service.name}</span>
            <.service_health_badge health={@service.health} />
          </div>

          <div class="text-sm text-base-content/70 mt-1">
            <span :if={@service.port}>Port: {@service.port}    • </span>
            Last restart: {@service.last_restart}
          </div>

          <div class="flex items-center gap-2 mt-2">
            <.service_status_badge status={@service.status} />
            <span :if={@service.auto_restart} class="badge badge-xs badge-info">Auto-restart</span>
          </div>
        </div>

        <div class="flex gap-1">
          <button
            class="btn btn-ghost btn-xs"
            title="View Logs"
          >
            <.icon name="hero-document-text" class="size-3" />
          </button>
          <button
            class="btn btn-warning btn-xs"
            phx-click="restart_service"
            phx-value-service={@service.name}
            title="Restart Service"
          >
            <.icon name="hero-arrow-path" class="size-3" />
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr :status, :string, required: true

  defp service_status_badge(assigns) do
    {badge_class, icon} =
      case assigns.status do
        "running" -> {"badge-success", "hero-check-circle"}
        "stopped" -> {"badge-error", "hero-x-circle"}
        "starting" -> {"badge-warning", "hero-arrow-path"}
        _ -> {"badge-ghost", "hero-question-mark-circle"}
      end

    assigns = assign(assigns, :badge_class, badge_class)
    assigns = assign(assigns, :icon, icon)

    ~H"""
    <div class={["badge badge-xs gap-1", @badge_class]}>
      <.icon name={@icon} class="size-2" /> {String.capitalize(@status)}
    </div>
    """
  end

  attr :health, :string, required: true

  defp service_health_badge(assigns) do
    {badge_class, icon} =
      case assigns.health do
        "healthy" -> {"badge-success", "hero-heart"}
        "warning" -> {"badge-warning", "hero-exclamation-triangle"}
        "critical" -> {"badge-error", "hero-x-circle"}
        _ -> {"badge-ghost", "hero-question-mark-circle"}
      end

    assigns = assign(assigns, :badge_class, badge_class)
    assigns = assign(assigns, :icon, icon)

    ~H"""
    <div class={["badge badge-xs gap-1", @badge_class]}>
      <.icon name={@icon} class="size-2" /> {String.capitalize(@health)}
    </div>
    """
  end

  attr :message, :map, required: true

  defp message_bubble(assigns) do
    ~H"""
    <div class={[
      "flex",
      @message.role == "user" && "justify-end",
      @message.role == "assistant" && "justify-start"
    ]}>
      <div class={[
        "max-w-xs lg:max-w-md px-4 py-2 rounded-lg",
        @message.role == "user" && "bg-primary text-primary-content",
        @message.role == "assistant" && "bg-base-300 text-base-content"
      ]}>
        <p class="text-sm">{@message.content}</p>

        <p class="text-xs opacity-70 mt-1">{@message.timestamp}</p>
      </div>
    </div>
    """
  end
end
