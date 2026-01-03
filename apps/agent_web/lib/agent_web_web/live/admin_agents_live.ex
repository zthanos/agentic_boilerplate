defmodule AgentWebWeb.AdminAgentsLive do
  @moduledoc """
  Admin agents management LiveView for agent configuration and monitoring.
  Provides interface for agent management, performance monitoring, and version control.
  """
  use AgentWebWeb, :live_view
  require AgentWebWeb.AdminErrorHandler
  alias AgentWebWeb.{AdminLayouts, AdminErrorHandler}
  alias AgentInfra.StoreEcto.AgentStore

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(AgentWeb.PubSub, "admin:agents")
    end

    {:ok,
     socket
     |> assign(:current_page, :agents)
     |> assign(:current_section, :management)
     |> assign(:sidebar_collapsed, false)
     |> assign(:page_title, "Agent Management")
     |> assign(:view_mode, :list)
     |> assign(:selected_agent, nil)
     |> load_agents_data()}
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
  def handle_event("view_agent", %{"agent_id" => agent_id}, socket) do
    agent = Enum.find(socket.assigns.agents, &(&1.id == agent_id))

    {:noreply,
     socket
     |> assign(:selected_agent, agent)
     |> assign(:view_mode, :detail)}
  end

  @impl true
  def handle_event("back_to_list", _params, socket) do
    {:noreply,
     socket
     |> assign(:view_mode, :list)
     |> assign(:selected_agent, nil)}
  end

  @impl true
  def handle_event("toggle_agent", %{"agent_id" => _agent_id}, socket) do
    # TODO: Implement agent toggle
    {:noreply, put_flash(socket, :info, "Agent status updated")}
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
  def render(assigns) do
    ~H"""
    <AdminLayouts.admin
      flash={@flash}
      current_page={@current_page}
      current_section={@current_section}
      sidebar_collapsed={@sidebar_collapsed}
    >
      <div class="mb-8">
        <.header>
          Agent Management
          <:subtitle>Configure and monitor AI agents, versions, and performance</:subtitle>

          <:actions>
            <button
              :if={@view_mode != :list}
              class="btn btn-outline btn-sm"
              phx-click="back_to_list"
            >
              <.icon name="hero-arrow-left" class="size-4 mr-2" /> Back to List
            </button>
          </:actions>
        </.header>
      </div>

      <div :if={@view_mode == :list}>
        <.agents_list agents={@agents} agent_stats={@agent_stats} />
      </div>

      <div :if={@view_mode == :detail && @selected_agent}>
        <.agent_detail agent={@selected_agent} />
      </div>
    </AdminLayouts.admin>
    """
  end

  defp load_agents_data(socket) do
    AdminErrorHandler.handle_data_loading(socket, :agents, fn ->
      # Load actual agents from database
      case AgentStore.list() do
        {:ok, agents} ->
          ui_agents = Enum.map(agents, &convert_agent_to_ui_format/1)
          agent_stats = calculate_agent_stats(ui_agents)

          %{
            agents: ui_agents,
            agent_stats: agent_stats
          }

        {:error, _error} ->
          # Fallback to empty data
          %{
            agents: [],
            agent_stats: %{total: 0, active: 0, inactive: 0, error: 0}
          }
      end
    end)
    |> case do
      %{agents: %{agents: agents, agent_stats: agent_stats}} ->
        socket
        |> assign(:agents, agents)
        |> assign(:agent_stats, agent_stats)

      socket ->
        # Error case - use fallback data
        socket
        |> assign(:agents, [])
        |> assign(:agent_stats, %{total: 0, active: 0, inactive: 0, error: 0})
    end
  end

  # Convert Agent domain struct to UI format
  defp convert_agent_to_ui_format(%AgentCore.Llm.Agent.Definition{} = agent) do
    %{
      id: agent.id,
      # Use ID as name for now
      name: agent.id,
      # Default type
      type: "workflow",
      # Default status
      status: "active",
      version: to_string(agent.version),
      # Not available in Definition
      model: "N/A",
      # Not available in Definition
      created_at: "N/A",
      description: "Agent definition v#{agent.version}",
      performance: %{
        success_rate: 95.0,
        avg_response_time: 1200,
        total_executions: 0
      },
      config: %{
        max_iterations: 10,
        timeout: 30000,
        retry_count: 3
      }
    }
  end

  defp get_mock_agents do
    [
      %{
        id: "agent_001",
        name: "ChatBot-v2",
        type: "conversational",
        status: "active",
        version: "2.1.0",
        model: "gpt-4",
        created_at: "2024-01-15",
        last_updated: "2024-02-01",
        performance: %{
          avg_response_time: "1.2s",
          success_rate: "98.5%",
          total_requests: 1250,
          errors: 18
        },
        config: %{
          temperature: 0.7,
          max_tokens: 2048,
          timeout: 30
        }
      },
      %{
        id: "agent_002",
        name: "DataAnalyzer",
        type: "analytical",
        status: "active",
        version: "1.5.2",
        model: "gpt-4",
        created_at: "2024-01-20",
        last_updated: "2024-01-28",
        performance: %{
          avg_response_time: "2.8s",
          success_rate: "96.2%",
          total_requests: 890,
          errors: 34
        },
        config: %{
          temperature: 0.3,
          max_tokens: 4096,
          timeout: 60
        }
      }
    ]
  end

  defp calculate_agent_stats(agents) do
    %{
      total: length(agents),
      active: Enum.count(agents, &(&1.status == "active")),
      inactive: Enum.count(agents, &(&1.status == "inactive"))
    }
  end

  attr :agents, :list, required: true
  attr :agent_stats, :map, required: true

  defp agents_list(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
        <.stat_card title="Total Agents" value={@agent_stats.total} color="primary" />
        <.stat_card title="Active" value={@agent_stats.active} color="success" />
        <.stat_card title="Inactive" value={@agent_stats.inactive} color="warning" />
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <.agent_card :for={agent <- @agents} agent={agent} />
      </div>
    </div>
    """
  end

  attr :agent, :map, required: true

  defp agent_card(assigns) do
    ~H"""
    <div class="card bg-base-200 shadow-sm hover:shadow-md transition-shadow">
      <div class="card-body">
        <div class="flex justify-between items-start">
          <div>
            <h3 class="card-title">{@agent.name}</h3>

            <div class="flex gap-2 mt-2">
              <.agent_status_badge status={@agent.status} />
              <div class="badge badge-outline">{@agent.type}</div>

              <div class="badge badge-ghost">v{@agent.version}</div>
            </div>
          </div>

          <div class="dropdown dropdown-end">
            <div tabindex="0" role="button" class="btn btn-ghost btn-sm">
              <.icon name="hero-ellipsis-vertical" class="size-4" />
            </div>

            <ul class="dropdown-content menu bg-base-100 rounded-box z-[1] w-52 p-2 shadow">
              <li>
                <button phx-click="view_agent" phx-value-agent_id={@agent.id}>
                  <.icon name="hero-eye" class="size-4" /> View Details
                </button>
              </li>

              <li>
                <button phx-click="toggle_agent" phx-value-agent_id={@agent.id}>
                  <.icon name="hero-power" class="size-4" /> {if @agent.status == "active",
                    do: "Deactivate",
                    else: "Activate"}
                </button>
              </li>
            </ul>
          </div>
        </div>

        <div class="mt-4 space-y-2">
          <div class="flex justify-between text-sm">
            <span class="text-base-content/70">Model:</span> <span>{@agent.model}</span>
          </div>

          <div class="flex justify-between text-sm">
            <span class="text-base-content/70">Response Time:</span>
            <span>{@agent.performance.avg_response_time}</span>
          </div>

          <div class="flex justify-between text-sm">
            <span class="text-base-content/70">Success Rate:</span>
            <span class="text-success">{@agent.performance.success_rate}</span>
          </div>

          <div class="flex justify-between text-sm">
            <span class="text-base-content/70">Total Requests:</span>
            <span>{@agent.performance.total_requests}</span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :agent, :map, required: true

  defp agent_detail(assigns) do
    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
      <div class="lg:col-span-2 space-y-6">
        <div class="card bg-base-200 shadow-sm">
          <div class="card-body">
            <div class="flex justify-between items-start">
              <div>
                <h3 class="text-xl font-semibold">{@agent.name}</h3>

                <p class="text-base-content/70">Version {@agent.version}</p>

                <div class="flex gap-2 mt-2">
                  <.agent_status_badge status={@agent.status} />
                  <div class="badge badge-outline">{@agent.type}</div>
                </div>
              </div>
            </div>
          </div>
        </div>

        <div class="card bg-base-200 shadow-sm">
          <div class="card-body">
            <h4 class="card-title">Configuration</h4>

            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <p class="text-sm text-base-content/70">Model</p>

                <p class="font-medium">{@agent.model}</p>
              </div>

              <div>
                <p class="text-sm text-base-content/70">Temperature</p>

                <p class="font-medium">{@agent.config.temperature}</p>
              </div>

              <div>
                <p class="text-sm text-base-content/70">Max Tokens</p>

                <p class="font-medium">{@agent.config.max_tokens}</p>
              </div>

              <div>
                <p class="text-sm text-base-content/70">Timeout</p>

                <p class="font-medium">{@agent.config.timeout}s</p>
              </div>
            </div>
          </div>
        </div>
      </div>

      <div class="space-y-6">
        <div class="card bg-base-200 shadow-sm">
          <div class="card-body">
            <h4 class="card-title">Performance</h4>

            <div class="space-y-3">
              <div>
                <p class="text-sm text-base-content/70">Avg Response Time</p>

                <p class="font-medium">{@agent.performance.avg_response_time}</p>
              </div>

              <div>
                <p class="text-sm text-base-content/70">Success Rate</p>

                <p class="font-medium text-success">{@agent.performance.success_rate}</p>
              </div>

              <div>
                <p class="text-sm text-base-content/70">Total Requests</p>

                <p class="font-medium">{@agent.performance.total_requests}</p>
              </div>

              <div>
                <p class="text-sm text-base-content/70">Errors</p>

                <p class="font-medium text-error">{@agent.performance.errors}</p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :value, :any, required: true
  attr :color, :string, required: true

  defp stat_card(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-sm">
      <div class="card-body p-4 text-center">
        <div class={["text-2xl font-bold", "text-#{@color}"]}>{@value}</div>

        <div class="text-sm text-base-content/70">{@title}</div>
      </div>
    </div>
    """
  end

  attr :status, :string, required: true

  defp agent_status_badge(assigns) do
    {badge_class, icon} =
      case assigns.status do
        "active" -> {"badge-success", "hero-check-circle"}
        "inactive" -> {"badge-error", "hero-x-circle"}
        _ -> {"badge-ghost", "hero-question-mark-circle"}
      end

    assigns = assign(assigns, :badge_class, badge_class)
    assigns = assign(assigns, :icon, icon)

    ~H"""
    <div class={["badge badge-sm gap-1", @badge_class]}>
      <.icon name={@icon} class="size-3" /> {String.capitalize(@status)}
    </div>
    """
  end
end
