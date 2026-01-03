defmodule AgentWebWeb.AdminTestingLive do
  @moduledoc """
  Admin testing management LiveView for agent testing and validation.
  Provides interface for test suite management, execution results, and performance benchmarking.
  """
  use AgentWebWeb, :live_view
  alias AgentWebWeb.AdminLayouts

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(AgentWeb.PubSub, "admin:testing")
    end

    {:ok,
     socket
     |> assign(:current_page, :testing)
     |> assign(:current_section, :management)
     |> assign(:sidebar_collapsed, false)
     |> assign(:page_title, "Agent Testing")
     |> assign(:view_mode, :overview)
     |> assign(:selected_test, nil)
     |> load_testing_data()}
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
  def handle_event("switch_view", %{"view" => view}, socket) do
    {:noreply, assign(socket, :view_mode, String.to_atom(view))}
  end

  @impl true
  def handle_event("run_test", %{"test_id" => _test_id}, socket) do
    # TODO: Implement test execution
    {:noreply, put_flash(socket, :info, "Test execution started")}
  end

  @impl true
  def handle_event("view_test", %{"test_id" => test_id}, socket) do
    test = Enum.find(socket.assigns.test_suites, &(&1.id == test_id))

    {:noreply,
     socket
     |> assign(:selected_test, test)
     |> assign(:view_mode, :detail)}
  end

  @impl true
  def handle_event("back_to_overview", _params, socket) do
    {:noreply,
     socket
     |> assign(:view_mode, :overview)
     |> assign(:selected_test, nil)}
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
          Agent Testing
          <:subtitle>
            Manage test suites, monitor execution results, and analyze performance
          </:subtitle>

          <:actions>
            <div class="flex gap-2">
              <button
                class={[
                  "btn btn-sm",
                  @view_mode == :overview && "btn-primary",
                  @view_mode != :overview && "btn-outline"
                ]}
                phx-click="switch_view"
                phx-value-view="overview"
              >
                <.icon name="hero-chart-bar" class="size-4 mr-2" /> Overview
              </button>
              <button
                class={[
                  "btn btn-sm",
                  @view_mode == :results && "btn-primary",
                  @view_mode != :results && "btn-outline"
                ]}
                phx-click="switch_view"
                phx-value-view="results"
              >
                <.icon name="hero-document-text" class="size-4 mr-2" /> Results
              </button>
              <button
                :if={@view_mode == :detail}
                class="btn btn-outline btn-sm"
                phx-click="back_to_overview"
              >
                <.icon name="hero-arrow-left" class="size-4 mr-2" /> Back
              </button>
            </div>
          </:actions>
        </.header>
      </div>

      <div :if={@view_mode == :overview}>
        <.testing_overview
          test_suites={@test_suites}
          testing_stats={@testing_stats}
          recent_results={@recent_results}
        />
      </div>

      <div :if={@view_mode == :results}><.test_results results={@test_results} /></div>

      <div :if={@view_mode == :detail && @selected_test}><.test_detail test={@selected_test} /></div>
    </AdminLayouts.admin>
    """
  end

  defp load_testing_data(socket) do
    test_suites = get_mock_test_suites()
    testing_stats = calculate_testing_stats(test_suites)
    recent_results = get_mock_recent_results()
    test_results = get_mock_test_results()

    socket
    |> assign(:test_suites, test_suites)
    |> assign(:testing_stats, testing_stats)
    |> assign(:recent_results, recent_results)
    |> assign(:test_results, test_results)
  end

  defp get_mock_test_suites do
    [
      %{
        id: "suite_001",
        name: "ChatBot Integration Tests",
        description: "End-to-end tests for ChatBot functionality",
        agent: "ChatBot-v2",
        test_count: 25,
        last_run: "2 hours ago",
        status: "passed",
        success_rate: "96.0%",
        avg_duration: "45s"
      },
      %{
        id: "suite_002",
        name: "DataAnalyzer Performance Tests",
        description: "Performance benchmarks for DataAnalyzer",
        agent: "DataAnalyzer",
        test_count: 15,
        last_run: "1 day ago",
        status: "failed",
        success_rate: "86.7%",
        avg_duration: "2m 15s"
      }
    ]
  end

  defp calculate_testing_stats(test_suites) do
    %{
      total_suites: length(test_suites),
      total_tests: Enum.sum(Enum.map(test_suites, & &1.test_count)),
      passed_suites: Enum.count(test_suites, &(&1.status == "passed")),
      failed_suites: Enum.count(test_suites, &(&1.status == "failed"))
    }
  end

  defp get_mock_recent_results do
    [
      %{
        id: "result_001",
        suite: "ChatBot Integration Tests",
        status: "passed",
        duration: "42s",
        timestamp: "2 hours ago",
        tests_passed: 24,
        tests_failed: 1
      },
      %{
        id: "result_002",
        suite: "DataAnalyzer Performance Tests",
        status: "failed",
        duration: "2m 18s",
        timestamp: "1 day ago",
        tests_passed: 13,
        tests_failed: 2
      }
    ]
  end

  defp get_mock_test_results do
    [
      %{
        id: "test_001",
        name: "Basic Chat Response",
        suite: "ChatBot Integration Tests",
        status: "passed",
        duration: "1.2s",
        message: "Test completed successfully"
      },
      %{
        id: "test_002",
        name: "Context Retention",
        suite: "ChatBot Integration Tests",
        status: "passed",
        duration: "2.1s",
        message: "Context properly maintained across conversation"
      },
      %{
        id: "test_003",
        name: "Error Handling",
        suite: "ChatBot Integration Tests",
        status: "failed",
        duration: "0.8s",
        message: "Expected error response not received"
      }
    ]
  end

  attr :test_suites, :list, required: true
  attr :testing_stats, :map, required: true
  attr :recent_results, :list, required: true

  defp testing_overview(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="grid grid-cols-1 md:grid-cols-4 gap-4">
        <.stat_card title="Test Suites" value={@testing_stats.total_suites} color="primary" />
        <.stat_card title="Total Tests" value={@testing_stats.total_tests} color="info" />
        <.stat_card title="Passed Suites" value={@testing_stats.passed_suites} color="success" />
        <.stat_card title="Failed Suites" value={@testing_stats.failed_suites} color="error" />
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <div class="card bg-base-200 shadow-sm">
          <div class="card-body">
            <h3 class="card-title">Test Suites</h3>

            <div class="space-y-3">
              <.test_suite_card :for={suite <- @test_suites} suite={suite} />
            </div>
          </div>
        </div>

        <div class="card bg-base-200 shadow-sm">
          <div class="card-body">
            <h3 class="card-title">Recent Results</h3>

            <div class="space-y-3">
              <.test_result_card :for={result <- @recent_results} result={result} />
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :results, :list, required: true

  defp test_results(assigns) do
    ~H"""
    <div class="card bg-base-200 shadow-sm">
      <div class="card-body">
        <h3 class="card-title">Test Results</h3>

        <div class="overflow-x-auto">
          <table class="table table-sm">
            <thead>
              <tr>
                <th>Test Name</th>

                <th>Suite</th>

                <th>Status</th>

                <th>Duration</th>

                <th>Message</th>
              </tr>
            </thead>

            <tbody>
              <tr :for={result <- @results}>
                <td class="font-medium">{result.name}</td>

                <td class="text-sm text-base-content/70">{result.suite}</td>

                <td><.test_status_badge status={result.status} /></td>

                <td class="text-sm">{result.duration}</td>

                <td class="text-sm text-base-content/70">{result.message}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  attr :test, :map, required: true

  defp test_detail(assigns) do
    ~H"""
    <div class="card bg-base-200 shadow-sm">
      <div class="card-body">
        <div class="flex justify-between items-start">
          <div>
            <h3 class="text-xl font-semibold">{@test.name}</h3>

            <p class="text-base-content/70">{@test.description}</p>

            <div class="flex gap-2 mt-2">
              <.test_status_badge status={@test.status} />
              <div class="badge badge-outline">{@test.agent}</div>
            </div>
          </div>

          <button
            class="btn btn-primary btn-sm"
            phx-click="run_test"
            phx-value-test_id={@test.id}
          >
            <.icon name="hero-play" class="size-4 mr-2" /> Run Tests
          </button>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-4 gap-4 mt-6">
          <div>
            <p class="text-sm text-base-content/70">Test Count</p>

            <p class="text-2xl font-bold">{@test.test_count}</p>
          </div>

          <div>
            <p class="text-sm text-base-content/70">Success Rate</p>

            <p class="text-2xl font-bold text-success">{@test.success_rate}</p>
          </div>

          <div>
            <p class="text-sm text-base-content/70">Avg Duration</p>

            <p class="text-2xl font-bold">{@test.avg_duration}</p>
          </div>

          <div>
            <p class="text-sm text-base-content/70">Last Run</p>

            <p class="text-2xl font-bold">{@test.last_run}</p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :suite, :map, required: true

  defp test_suite_card(assigns) do
    ~H"""
    <div
      class="p-3 bg-base-100 rounded-lg hover:bg-base-300 transition-colors cursor-pointer"
      phx-click="view_test"
      phx-value-test_id={@suite.id}
    >
      <div class="flex justify-between items-start">
        <div class="flex-1">
          <div class="flex items-center gap-2">
            <span class="font-medium">{@suite.name}</span>
            <.test_status_badge status={@suite.status} />
          </div>

          <p class="text-sm text-base-content/70 mt-1">{@suite.description}</p>

          <div class="flex gap-4 text-xs text-base-content/50 mt-2">
            <span>{@suite.test_count} tests</span> <span>Last run: {@suite.last_run}</span>
            <span>Success: {@suite.success_rate}</span>
          </div>
        </div>

        <button
          class="btn btn-ghost btn-xs"
          phx-click="run_test"
          phx-value-test_id={@suite.id}
        >
          <.icon name="hero-play" class="size-3" />
        </button>
      </div>
    </div>
    """
  end

  attr :result, :map, required: true

  defp test_result_card(assigns) do
    ~H"""
    <div class="p-3 bg-base-100 rounded-lg">
      <div class="flex justify-between items-start">
        <div class="flex-1">
          <div class="flex items-center gap-2">
            <span class="font-medium">{@result.suite}</span>
            <.test_status_badge status={@result.status} />
          </div>

          <div class="flex gap-4 text-sm text-base-content/70 mt-1">
            <span>Duration: {@result.duration}</span> <span>Passed: {@result.tests_passed}</span>
            <span>Failed: {@result.tests_failed}</span>
          </div>

          <p class="text-xs text-base-content/50 mt-1">{@result.timestamp}</p>
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

  defp test_status_badge(assigns) do
    {badge_class, icon} =
      case assigns.status do
        "passed" -> {"badge-success", "hero-check-circle"}
        "failed" -> {"badge-error", "hero-x-circle"}
        "running" -> {"badge-warning", "hero-play"}
        "pending" -> {"badge-ghost", "hero-clock"}
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
end
