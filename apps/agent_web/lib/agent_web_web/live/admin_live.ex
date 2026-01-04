defmodule AgentWebWeb.AdminLive do
  @moduledoc """
  Main admin dashboard LiveView
  """
  use AgentWebWeb, :live_view
  require AgentWebWeb.AdminErrorHandler
  alias AgentWebWeb.{AdminLayouts, AdminErrorHandler}
  import AgentWebWeb.AdminErrorComponents

  @impl true
  def mount(_params, _session, socket) do
    AdminErrorHandler.handle_mount_error(socket, fn socket ->
      if connected?(socket) do
        Phoenix.PubSub.subscribe(AgentWeb.PubSub, "admin:metrics")
        Phoenix.PubSub.subscribe(AgentWeb.PubSub, "admin:health")
        Phoenix.PubSub.subscribe(AgentWeb.PubSub, "admin:activity")
        Phoenix.PubSub.subscribe(AgentWeb.PubSub, "admin:runs")
        :timer.send_interval(30_000, self(), :refresh_metrics)
      end

      socket
      |> assign(:current_page, :dashboard)
      |> assign(:current_section, :analytics)
      |> assign(:sidebar_collapsed, false)
      # Default state, will be updated by JS
      |> assign(:sidebar_collapsed, false)
      |> assign(:page_title, "Admin Dashboard")
      |> assign(:loading, false)
      |> assign(:error, nil)
      |> load_system_metrics_with_error_handling()
    end)
  end

  @impl true
  def handle_event("toggle_sidebar", _params, socket) do
    new_state = !socket.assigns.sidebar_collapsed
    {:noreply, assign(socket, :sidebar_collapsed, new_state)}
  end

  # Event από το JavaScript hook για persistence
  @impl true
  def handle_event("set_sidebar_state", %{"collapsed" => collapsed}, socket) do
    {:noreply, assign(socket, :sidebar_collapsed, collapsed)}
  end

  # Message από το LiveComponent
  @impl true
  def handle_info({:toggle_sidebar}, socket) do
    new_state = !socket.assigns.sidebar_collapsed
    {:noreply, assign(socket, :sidebar_collapsed, new_state)}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    # Δεν χρειάζεται να κάνουμε κάτι εδώ αν το current_page ορίζεται ήδη
    {:noreply, socket}
  end

  @impl true
  def handle_info({:toggle_sidebar}, socket) do
    new_state = !socket.assigns.sidebar_collapsed
    {:noreply, assign(socket, :sidebar_collapsed, new_state)}
  end

  @impl true
  def handle_event("set_sidebar_state", %{"collapsed" => collapsed}, socket) do
    {:noreply, assign(socket, :sidebar_collapsed, collapsed)}
  end

  @impl true
  def handle_info({:close_mobile_sidebar}, socket) do
    # On mobile, always close the sidebar when a navigation link is clicked
    {:noreply, assign(socket, :sidebar_collapsed, true)}
  end

  @impl true
  def handle_info(:refresh_metrics, socket) do
    {:noreply, load_system_metrics_with_error_handling(socket)}
  end

  @impl true
  def handle_info({:metrics_updated, metrics}, socket) do
    {:noreply,
     socket
     |> assign(:system_metrics, metrics)
     |> assign(:system_metrics_error, nil)}
  end

  @impl true
  def handle_info({:health_status_changed, status}, socket) do
    case socket.assigns[:system_metrics] do
      nil ->
        {:noreply, socket}

      metrics ->
        updated_metrics = Map.put(metrics, :health_status, status)
        {:noreply, assign(socket, :system_metrics, updated_metrics)}
    end
  end

  @impl true
  def handle_info({:new_activity, activity}, socket) do
    case socket.assigns[:system_metrics] do
      nil ->
        {:noreply, socket}

      metrics ->
        # Add new activity to the top of the list and keep only the latest 5
        current_activities = metrics.recent_activities || []
        updated_activities = [activity | current_activities] |> Enum.take(5)

        updated_metrics = Map.put(metrics, :recent_activities, updated_activities)
        {:noreply, assign(socket, :system_metrics, updated_metrics)}
    end
  end

  @impl true
  def handle_info({:run_created, _run}, socket) do
    # Update run count when new runs are created
    {:noreply, load_system_metrics_with_error_handling(socket)}
  end

  @impl true
  def handle_info({:run_completed, _run}, socket) do
    # Update metrics when runs complete
    {:noreply, load_system_metrics_with_error_handling(socket)}
  end

  @impl true
  def handle_info({:toggle_sidebar}, socket) do
    new_state = !socket.assigns.sidebar_collapsed
    {:noreply, assign(socket, :sidebar_collapsed, new_state)}
  end

  @impl true
  def handle_info({:metrics_error, error}, socket) do
    {:noreply,
     socket
     |> assign(:system_metrics_loading, false)
     |> assign(:system_metrics_error, AdminErrorHandler.format_error_message(error))
     |> put_flash(:error, "Failed to load system metrics")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AdminLayouts.admin
      flash={@flash}
      current_page={@current_page}
      current_section={@current_section}
      sidebar_collapsed={@sidebar_collapsed}
      loading={@loading}
      error={@error}
    >
      <!-- Dashboard Header -->
      <div class="mb-8">
        <.header>
          Admin Dashboard
          <:subtitle>
            System overview and key performance indicators
            <span class="inline-flex items-center gap-1 ml-2">
              <div class="w-2 h-2 bg-success rounded-full animate-pulse"></div>
              <span class="text-xs text-success">Live</span>
            </span>
          </:subtitle>

          <:actions>
            <button
              class="btn btn-primary btn-sm"
              phx-click="refresh_metrics"
              disabled={@system_metrics_loading}
            >
              <.icon
                name="hero-arrow-path"
                class={[
                  "size-4 mr-2",
                  @system_metrics_loading && "animate-spin"
                ]}
              /> Refresh
            </button>
          </:actions>
        </.header>
      </div>
      <!-- System Health Status -->
      <div class="mb-6">
        <.system_health_banner
          health_status={@system_metrics && @system_metrics.health_status}
          loading={@system_metrics_loading}
          error={@system_metrics_error}
        />
      </div>
      <!-- Main Dashboard Content -->
      <.card_wrapper
        title="System Metrics"
        loading={@system_metrics_loading}
        error={@system_metrics_error}
        retry_event="retry_metrics"
      >
        <!-- KPI Cards -->
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-8">
          <.kpi_card
            title="Total Runs"
            value={@system_metrics && @system_metrics.total_runs}
            icon="hero-play"
            trend={@system_metrics && @system_metrics.runs_trend}
            trend_positive={@system_metrics && @system_metrics.runs_trend_positive}
          />
          <.kpi_card
            title="Active Sessions"
            value={@system_metrics && @system_metrics.active_sessions}
            icon="hero-users"
            trend={@system_metrics && @system_metrics.sessions_trend}
            trend_positive={@system_metrics && @system_metrics.sessions_trend_positive}
          />
          <.kpi_card
            title="System Health"
            value={@system_metrics && @system_metrics.health_status}
            icon="hero-heart"
            trend={@system_metrics && @system_metrics.uptime}
            trend_positive={true}
          />
          <.kpi_card
            title="Avg Response"
            value={@system_metrics && @system_metrics.avg_response_time}
            icon="hero-clock"
            trend={@system_metrics && @system_metrics.response_trend}
            trend_positive={@system_metrics && @system_metrics.response_trend_positive}
          />
        </div>
        <!-- Charts and Analytics -->
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-8">
          <!-- Usage Chart -->
          <div class="card bg-base-200 shadow-sm">
            <div class="card-body">
              <h3 class="card-title text-lg">Usage Analytics</h3>

              <div class="h-64 flex items-center justify-center bg-base-100 rounded-lg">
                <div class="text-center">
                  <.icon name="hero-chart-bar" class="size-12 text-base-content/30 mx-auto mb-2" />
                  <p class="text-sm text-base-content/70">Chart visualization would go here</p>

                  <p class="text-xs text-base-content/50">
                    Daily executions: {@system_metrics && @system_metrics.daily_executions}
                  </p>
                </div>
              </div>
            </div>
          </div>
          <!-- System Resources -->
          <div class="card bg-base-200 shadow-sm">
            <div class="card-body">
              <h3 class="card-title text-lg">System Resources</h3>

              <div class="space-y-4">
                <.resource_meter
                  label="CPU Usage"
                  value={(@system_metrics && @system_metrics.cpu_usage) || 0}
                  max={100}
                  unit="%"
                  color="primary"
                />
                <.resource_meter
                  label="Memory Usage"
                  value={(@system_metrics && @system_metrics.memory_usage) || 0}
                  max={100}
                  unit="%"
                  color="secondary"
                />
                <.resource_meter
                  label="Disk Usage"
                  value={(@system_metrics && @system_metrics.disk_usage) || 0}
                  max={100}
                  unit="%"
                  color="accent"
                />
              </div>
            </div>
          </div>
        </div>
        <!-- Recent Activity and Quick Actions -->
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-8">
          <!-- Recent Activity -->
          <div class="card bg-base-200 shadow-sm">
            <div class="card-body">
              <h3 class="card-title text-lg">Recent Activity</h3>

              <div :if={@system_metrics && @system_metrics.recent_activities} class="space-y-3">
                <.activity_item
                  :for={activity <- @system_metrics.recent_activities}
                  type={activity.type}
                  description={activity.description}
                  time={activity.time}
                  user={activity.user}
                />
              </div>

              <div
                :if={!@system_metrics || Enum.empty?(@system_metrics.recent_activities || [])}
                class="py-8"
              >
                <.empty_state
                  title="No recent activity"
                  message="System activity will appear here"
                  icon="hero-clock"
                />
              </div>

              <div class="card-actions justify-end mt-4">
                <a href="/admin/runs" class="btn btn-sm btn-ghost">View All</a>
              </div>
            </div>
          </div>
          <!-- Quick Actions -->
          <div class="card bg-base-200 shadow-sm">
            <div class="card-body">
              <h3 class="card-title text-lg">Quick Actions</h3>

              <div class="grid grid-cols-2 gap-3">
                <a href="/admin/agents" class="btn btn-outline">
                  <.icon name="hero-cpu-chip" class="size-4" /> Manage Agents
                </a>
                <a href="/admin/workflows" class="btn btn-outline">
                  <.icon name="hero-squares-2x2" class="size-4" /> Workflows
                </a>
                <a href="/admin/settings" class="btn btn-outline">
                  <.icon name="hero-cog-6-tooth" class="size-4" /> Settings
                </a>
                <a href="/admin/testing" class="btn btn-outline">
                  <.icon name="hero-beaker" class="size-4" /> Run Tests
                </a>
              </div>
            </div>
          </div>
        </div>
        <!-- System Status Details -->
        <div class="card bg-base-200 shadow-sm">
          <div class="card-body">
            <h3 class="card-title text-lg">System Status</h3>

            <div
              :if={@system_metrics && @system_metrics.services}
              class="grid grid-cols-1 md:grid-cols-3 gap-4"
            >
              <.status_indicator
                :for={service <- @system_metrics.services}
                label={service.name}
                status={service.status}
                details={service.details}
              />
            </div>

            <div :if={!@system_metrics || Enum.empty?(@system_metrics.services || [])} class="py-8">
              <.empty_state
                title="No service status available"
                message="Service health information will appear here"
                icon="hero-server"
              />
            </div>
          </div>
        </div>
      </.card_wrapper>
    </AdminLayouts.admin>
    """
  end

  # Load system metrics from various sources with comprehensive error handling
  defp load_system_metrics_with_error_handling(socket) do
    AdminErrorHandler.handle_data_loading(socket, :system_metrics, fn ->
      get_system_metrics_data()
    end)
  end

  # Get system metrics data (this would integrate with real services)
  defp get_system_metrics_data do
    # Simulate potential failure for demonstration
    if :rand.uniform(10) == 1 do
      raise "Simulated metrics loading failure"
    end

    %{
      # Core metrics
      total_runs: get_total_runs(),
      active_sessions: get_active_sessions(),
      health_status: get_system_health(),
      avg_response_time: get_avg_response_time(),

      # Trends
      runs_trend: "+12%",
      runs_trend_positive: true,
      sessions_trend: "+5%",
      sessions_trend_positive: true,
      response_trend: "-0.3s",
      response_trend_positive: true,
      uptime: "99.9%",

      # Usage analytics
      daily_executions: get_daily_executions(),
      monthly_executions: get_monthly_executions(),

      # System resources
      cpu_usage: get_cpu_usage(),
      memory_usage: get_memory_usage(),
      disk_usage: get_disk_usage(),

      # Recent activities
      recent_activities: get_recent_activities(),

      # Services status
      services: get_services_status()
    }
  end

  # Load system metrics from various sources (legacy function for compatibility)
  defp load_system_metrics(socket) do
    assign(socket, :system_metrics, get_system_metrics_data())
  end

  # Metric collection functions (integrate with AgentCore contexts)
  defp get_total_runs do
    # TODO: Integrate with AgentCore.Runs.count_total()
    1_234
  end

  defp get_active_sessions do
    # TODO: Integrate with session tracking
    42
  end

  defp get_system_health do
    # TODO: Integrate with health check system
    "Healthy"
  end

  defp get_avg_response_time do
    # TODO: Calculate from recent runs
    "1.2s"
  end

  defp get_daily_executions do
    # TODO: Get today's execution count
    156
  end

  defp get_monthly_executions do
    # TODO: Get this month's execution count
    4_892
  end

  defp get_cpu_usage do
    # TODO: Get actual CPU usage
    :rand.uniform(30) + 20
  end

  defp get_memory_usage do
    # TODO: Get actual memory usage
    :rand.uniform(40) + 30
  end

  defp get_disk_usage do
    # TODO: Get actual disk usage
    :rand.uniform(20) + 15
  end

  defp get_recent_activities do
    [
      %{
        type: "execution",
        description: "Chat execution completed successfully",
        time: "2 minutes ago",
        user: "system"
      },
      %{
        type: "agent",
        description: "New agent 'Assistant-v2' deployed",
        time: "15 minutes ago",
        user: "admin"
      },
      %{
        type: "user",
        description: "User profile updated",
        time: "1 hour ago",
        user: "user123"
      },
      %{
        type: "system",
        description: "System health check completed",
        time: "2 hours ago",
        user: "system"
      }
    ]
  end

  defp get_services_status do
    [
      %{name: "Database", status: "healthy", details: "Connection: 5ms"},
      %{name: "LLM Services", status: "healthy", details: "All providers online"},
      %{name: "Background Jobs", status: "healthy", details: "Queue: 3 pending"}
    ]
  end

  # Helper components for the dashboard

  attr :health_status, :string, default: nil
  attr :loading, :boolean, default: false
  attr :error, :string, default: nil

  defp system_health_banner(assigns) do
    ~H"""
    <div :if={@loading} class="alert alert-info">
      <div class="loading loading-spinner loading-sm"></div>
      <span>Checking system health...</span>
    </div>

    <div :if={@error && !@loading} class="alert alert-error">
      <.icon name="hero-exclamation-circle" class="size-6" />
      <span>Unable to check system health: {@error}</span>
    </div>

    <div
      :if={@health_status && !@loading && !@error}
      class={[
        "alert",
        @health_status == "Healthy" && "alert-success",
        @health_status == "Warning" && "alert-warning",
        @health_status == "Critical" && "alert-error",
        !(@health_status in ["Healthy", "Warning", "Critical"]) && "alert-info"
      ]}
    >
      <.icon
        name={
          case @health_status do
            "Healthy" -> "hero-check-circle"
            "Warning" -> "hero-exclamation-triangle"
            "Critical" -> "hero-x-circle"
            _ -> "hero-information-circle"
          end
        }
        class="size-6"
      />
      <span class="font-medium">
        {case @health_status do
          "Healthy" -> "All systems operational"
          "Warning" -> "Some services need attention"
          "Critical" -> "Critical issues detected"
          _ -> "System status unknown"
        end}
      </span>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :value, :any, required: true
  attr :icon, :string, required: true
  attr :trend, :string, default: nil
  attr :trend_positive, :boolean, default: true

  defp kpi_card(assigns) do
    ~H"""
    <div class="card bg-base-200 shadow-sm">
      <div class="card-body p-6">
        <div class="flex items-center justify-between">
          <div>
            <p class="text-sm text-base-content/70">{@title}</p>

            <p class="text-2xl font-bold">{@value}</p>

            <p
              :if={@trend}
              class={[
                "text-sm font-medium",
                @trend_positive && "text-success",
                !@trend_positive && "text-error"
              ]}
            >
              {@trend}
            </p>
          </div>

          <div class="p-3 bg-primary/10 rounded-lg">
            <.icon name={@icon} class="size-6 text-primary" />
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :max, :integer, required: true
  attr :unit, :string, default: ""
  attr :color, :string, default: "primary"

  defp resource_meter(assigns) do
    percentage = min(100, round(assigns.value / assigns.max * 100))
    assigns = assign(assigns, :percentage, percentage)

    ~H"""
    <div>
      <div class="flex justify-between text-sm mb-1">
        <span>{@label}</span> <span>{@value}{@unit}</span>
      </div>

      <div class="w-full bg-base-300 rounded-full h-2">
        <div
          class={["h-2 rounded-full", "bg-#{@color}"]}
          style={"width: #{@percentage}%"}
        >
        </div>
      </div>
    </div>
    """
  end

  attr :type, :string, required: true
  attr :description, :string, required: true
  attr :time, :string, required: true
  attr :user, :string, required: true

  defp activity_item(assigns) do
    icon =
      case assigns.type do
        "execution" -> "hero-play"
        "agent" -> "hero-cpu-chip"
        "user" -> "hero-user"
        "system" -> "hero-cog-6-tooth"
        _ -> "hero-information-circle"
      end

    assigns = assign(assigns, :icon, icon)

    ~H"""
    <div class="flex items-center gap-3">
      <div class="p-2 bg-primary/10 rounded-lg">
        <.icon name={@icon} class="size-4 text-primary" />
      </div>

      <div class="flex-1">
        <p class="text-sm">{@description}</p>

        <p class="text-xs text-base-content/50">{@time} • {@user}</p>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :status, :string, required: true
  attr :details, :string, required: true

  defp status_indicator(assigns) do
    status_class =
      case assigns.status do
        "healthy" -> "text-success"
        "warning" -> "text-warning"
        "error" -> "text-error"
        _ -> "text-base-content"
      end

    status_icon =
      case assigns.status do
        "healthy" -> "hero-check-circle"
        "warning" -> "hero-exclamation-triangle"
        "error" -> "hero-x-circle"
        _ -> "hero-question-mark-circle"
      end

    assigns = assign(assigns, :status_class, status_class)
    assigns = assign(assigns, :status_icon, status_icon)

    ~H"""
    <div class="flex items-center gap-3">
      <.icon name={@status_icon} class={"size-5 " <> @status_class} />
      <div>
        <p class="font-medium">{@label}</p>

        <p class="text-sm text-base-content/70">{@details}</p>
      </div>
    </div>
    """
  end
end
