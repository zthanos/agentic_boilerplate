defmodule AgentWebWeb.AdminRunHistoryLive do
  @moduledoc """
  Admin run history LiveView for viewing and managing execution history.
  Provides paginated table with filtering, search, and export capabilities.
  """
  use AgentWebWeb, :live_view
  alias AgentWebWeb.AdminLayouts

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to real-time updates
      Phoenix.PubSub.subscribe(AgentWeb.PubSub, "admin:runs")
      Phoenix.PubSub.subscribe(AgentWeb.PubSub, "admin:metrics")
    end

    {:ok,
     socket
     |> assign(:current_page, :runs)
     |> assign(:current_section, :analytics)
     |> assign(:sidebar_collapsed, false)
     |> assign(:page_title, "Run History")
     |> assign(:search_query, "")
     |> assign(:status_filter, "all")
     |> assign(:date_filter, "all")
     |> assign(:page, 1)
     |> assign(:per_page, 20)
     |> load_runs()}
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
  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    {:noreply,
     socket
     |> assign(:search_query, query)
     |> assign(:page, 1)
     |> load_runs()}
  end

  @impl true
  def handle_event("filter_status", %{"status" => status}, socket) do
    {:noreply,
     socket
     |> assign(:status_filter, status)
     |> assign(:page, 1)
     |> load_runs()}
  end

  @impl true
  def handle_event("filter_date", %{"date" => date}, socket) do
    {:noreply,
     socket
     |> assign(:date_filter, date)
     |> assign(:page, 1)
     |> load_runs()}
  end

  @impl true
  def handle_event("change_page", %{"page" => page}, socket) do
    page = String.to_integer(page)

    {:noreply,
     socket
     |> assign(:page, page)
     |> load_runs()}
  end

  @impl true
  def handle_event("export_runs", _params, socket) do
    # TODO: Implement CSV export functionality
    {:noreply, put_flash(socket, :info, "Export functionality coming soon")}
  end

  @impl true
  def handle_event("view_run", %{"id" => run_id}, socket) do
    # TODO: Navigate to detailed run view or show modal
    {:noreply, put_flash(socket, :info, "Viewing run #{run_id}")}
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
  def handle_info({:run_created, _run}, socket) do
    # Refresh runs when a new run is created
    {:noreply, load_runs(socket)}
  end

  @impl true
  def handle_info({:run_updated, _run}, socket) do
    # Refresh runs when a run is updated
    {:noreply, load_runs(socket)}
  end

  @impl true
  def handle_info({:run_completed, _run}, socket) do
    # Refresh runs when a run completes
    {:noreply, load_runs(socket)}
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
          Run History
          <:subtitle>
            View and manage execution history with filtering and search capabilities
            <span class="inline-flex items-center gap-1 ml-2">
              <div class="w-2 h-2 bg-success rounded-full animate-pulse"></div>
              <span class="text-xs text-success">Live Updates</span>
            </span>
          </:subtitle>

          <:actions>
            <button
              class="btn btn-outline btn-sm"
              phx-click="export_runs"
            >
              <.icon name="hero-arrow-down-tray" class="size-4 mr-2" /> Export
            </button>
          </:actions>
        </.header>
      </div>
      <!-- Filters and Search -->
      <div class="card bg-base-200 shadow-sm mb-6">
        <div class="card-body">
          <div class="flex flex-col lg:flex-row gap-4">
            <!-- Search -->
            <div class="flex-1">
              <.form for={%{}} as={:search} phx-change="search" class="flex gap-2">
                <.input
                  type="text"
                  name="query"
                  value={@search_query}
                  placeholder="Search runs by ID, agent, or description..."
                  class="flex-1"
                />
                <button type="submit" class="btn btn-primary">
                  <.icon name="hero-magnifying-glass" class="size-4" />
                </button>
              </.form>
            </div>
            <!-- Status Filter -->
            <div class="flex gap-2">
              <select
                class="select select-bordered"
                phx-change="filter_status"
                name="status"
              >
                <option value="all" selected={@status_filter == "all"}>All Status</option>

                <option value="completed" selected={@status_filter == "completed"}>Completed</option>

                <option value="failed" selected={@status_filter == "failed"}>Failed</option>

                <option value="running" selected={@status_filter == "running"}>Running</option>
              </select>
              <!-- Date Filter -->
              <select
                class="select select-bordered"
                phx-change="filter_date"
                name="date"
              >
                <option value="all" selected={@date_filter == "all"}>All Time</option>

                <option value="today" selected={@date_filter == "today"}>Today</option>

                <option value="week" selected={@date_filter == "week"}>This Week</option>

                <option value="month" selected={@date_filter == "month"}>This Month</option>
              </select>
            </div>
          </div>
        </div>
      </div>
      <!-- Summary Stats -->
      <div class="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
        <.summary_card
          title="Total Runs"
          value={@runs_summary.total}
          icon="hero-play"
          color="primary"
        />
        <.summary_card
          title="Completed"
          value={@runs_summary.completed}
          icon="hero-check-circle"
          color="success"
        />
        <.summary_card
          title="Failed"
          value={@runs_summary.failed}
          icon="hero-x-circle"
          color="error"
        />
        <.summary_card
          title="Running"
          value={@runs_summary.running}
          icon="hero-arrow-path"
          color="warning"
        />
      </div>
      <!-- Runs Table -->
      <div class="card bg-base-200 shadow-sm">
        <div class="card-body">
          <div class="overflow-x-auto">
            <table class="table table-zebra">
              <thead>
                <tr>
                  <th>Run ID</th>

                  <th>Agent</th>

                  <th>Status</th>

                  <th>Started</th>

                  <th>Duration</th>

                  <th>User</th>

                  <th>Actions</th>
                </tr>
              </thead>

              <tbody>
                <tr :for={run <- @runs} class="hover">
                  <td>
                    <div class="font-mono text-sm">{String.slice(run.id, 0, 8)}...</div>
                  </td>

                  <td>
                    <div class="flex items-center gap-2">
                      <.icon name="hero-cpu-chip" class="size-4 text-primary" />
                      <span class="font-medium">{run.agent_name}</span>
                    </div>
                  </td>

                  <td><.status_badge status={run.status} /></td>

                  <td>
                    <div class="text-sm">
                      <div>{run.started_at_date}</div>

                      <div class="text-base-content/70">{run.started_at_time}</div>
                    </div>
                  </td>

                  <td><span class="font-mono text-sm">{run.duration}</span></td>

                  <td>
                    <div class="flex items-center gap-2">
                      <.icon name="hero-user" class="size-4 text-base-content/70" />
                      <span>{run.user}</span>
                    </div>
                  </td>

                  <td>
                    <div class="flex gap-1">
                      <button
                        class="btn btn-ghost btn-xs"
                        phx-click="view_run"
                        phx-value-id={run.id}
                      >
                        <.icon name="hero-eye" class="size-3" />
                      </button>
                      <button class="btn btn-ghost btn-xs">
                        <.icon name="hero-arrow-down-tray" class="size-3" />
                      </button>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <!-- Pagination -->
          <div class="flex justify-between items-center mt-6">
            <div class="text-sm text-base-content/70">
              Showing {@pagination.start}-{@pagination.end} of {@pagination.total} runs
            </div>

            <div class="join">
              <button
                class="join-item btn btn-sm"
                phx-click="change_page"
                phx-value-page={@page - 1}
                disabled={@page == 1}
              >
                <.icon name="hero-chevron-left" class="size-4" />
              </button>
              <button
                :for={page_num <- @pagination.pages}
                class={[
                  "join-item btn btn-sm",
                  page_num == @page && "btn-active"
                ]}
                phx-click="change_page"
                phx-value-page={page_num}
              >
                {page_num}
              </button>
              <button
                class="join-item btn btn-sm"
                phx-click="change_page"
                phx-value-page={@page + 1}
                disabled={@page == @pagination.total_pages}
              >
                <.icon name="hero-chevron-right" class="size-4" />
              </button>
            </div>
          </div>
        </div>
      </div>
    </AdminLayouts.admin>
    """
  end

  # Load runs data with filtering and pagination
  defp load_runs(socket) do
    # TODO: Integrate with AgentCore.Runs context
    runs = get_mock_runs(socket.assigns)
    summary = calculate_runs_summary(runs)
    pagination = calculate_pagination(socket.assigns, length(runs))

    socket
    |> assign(:runs, runs)
    |> assign(:runs_summary, summary)
    |> assign(:pagination, pagination)
  end

  # Mock data - replace with actual AgentCore integration
  defp get_mock_runs(assigns) do
    base_runs = [
      %{
        id: "run_abc123def456",
        agent_name: "ChatBot-v2",
        status: "completed",
        started_at_date: "2024-01-03",
        started_at_time: "14:30:15",
        duration: "2.3s",
        user: "john.doe"
      },
      %{
        id: "run_def456ghi789",
        agent_name: "Assistant-Pro",
        status: "failed",
        started_at_date: "2024-01-03",
        started_at_time: "14:25:42",
        duration: "1.8s",
        user: "jane.smith"
      },
      %{
        id: "run_ghi789jkl012",
        agent_name: "DataAnalyzer",
        status: "running",
        started_at_date: "2024-01-03",
        started_at_time: "14:20:10",
        duration: "45.2s",
        user: "admin"
      },
      %{
        id: "run_jkl012mno345",
        agent_name: "CodeReviewer",
        status: "completed",
        started_at_date: "2024-01-03",
        started_at_time: "14:15:33",
        duration: "5.7s",
        user: "dev.team"
      },
      %{
        id: "run_mno345pqr678",
        agent_name: "ChatBot-v2",
        status: "completed",
        started_at_date: "2024-01-03",
        started_at_time: "14:10:22",
        duration: "1.9s",
        user: "john.doe"
      }
    ]

    # Apply filters
    filtered_runs =
      base_runs
      |> filter_by_search(assigns.search_query)
      |> filter_by_status(assigns.status_filter)
      |> filter_by_date(assigns.date_filter)

    # Apply pagination
    start_index = (assigns.page - 1) * assigns.per_page
    Enum.slice(filtered_runs, start_index, assigns.per_page)
  end

  defp filter_by_search(runs, ""), do: runs

  defp filter_by_search(runs, query) do
    query = String.downcase(query)

    Enum.filter(runs, fn run ->
      String.contains?(String.downcase(run.id), query) ||
        String.contains?(String.downcase(run.agent_name), query) ||
        String.contains?(String.downcase(run.user), query)
    end)
  end

  defp filter_by_status(runs, "all"), do: runs

  defp filter_by_status(runs, status) do
    Enum.filter(runs, &(&1.status == status))
  end

  defp filter_by_date(runs, "all"), do: runs

  defp filter_by_date(runs, _date_filter) do
    # TODO: Implement actual date filtering
    runs
  end

  defp calculate_runs_summary(runs) do
    %{
      total: length(runs),
      completed: Enum.count(runs, &(&1.status == "completed")),
      failed: Enum.count(runs, &(&1.status == "failed")),
      running: Enum.count(runs, &(&1.status == "running"))
    }
  end

  defp calculate_pagination(assigns, total_filtered) do
    total_pages = max(1, ceil(total_filtered / assigns.per_page))
    start_item = (assigns.page - 1) * assigns.per_page + 1
    end_item = min(assigns.page * assigns.per_page, total_filtered)

    # Generate page numbers for pagination
    pages =
      cond do
        total_pages <= 7 ->
          1..total_pages |> Enum.to_list()

        assigns.page <= 4 ->
          [1, 2, 3, 4, 5, "...", total_pages]

        assigns.page >= total_pages - 3 ->
          [
            1,
            "...",
            total_pages - 4,
            total_pages - 3,
            total_pages - 2,
            total_pages - 1,
            total_pages
          ]

        true ->
          [1, "...", assigns.page - 1, assigns.page, assigns.page + 1, "...", total_pages]
      end

    %{
      total: total_filtered,
      total_pages: total_pages,
      start: start_item,
      end: end_item,
      pages: Enum.filter(pages, &is_integer/1)
    }
  end

  # Helper components

  attr :title, :string, required: true
  attr :value, :integer, required: true
  attr :icon, :string, required: true
  attr :color, :string, required: true

  defp summary_card(assigns) do
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

  attr :status, :string, required: true

  defp status_badge(assigns) do
    {badge_class, icon} =
      case assigns.status do
        "completed" -> {"badge-success", "hero-check-circle"}
        "failed" -> {"badge-error", "hero-x-circle"}
        "running" -> {"badge-warning", "hero-arrow-path"}
        _ -> {"badge-ghost", "hero-question-mark-circle"}
      end

    assigns = assign(assigns, :badge_class, badge_class)
    assigns = assign(assigns, :icon, icon)

    ~H"""
    <div class={["badge gap-1", @badge_class]}>
      <.icon name={@icon} class="size-3" /> {String.capitalize(@status)}
    </div>
    """
  end
end
