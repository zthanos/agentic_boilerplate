defmodule AgentWebWeb.AdminWorkflowsLive do
  @moduledoc """
  Admin workflows management LiveView for agent workflow definition and monitoring.
  Provides interface for managing agent execution workflows, step definitions, and execution monitoring.
  """
  use AgentWebWeb, :live_view
  require AgentWebWeb.AdminErrorHandler
  alias AgentWebWeb.{AdminLayouts, AdminErrorHandler}
  alias AgentCore.WorkflowEngine.Registry

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(AgentWeb.PubSub, "admin:workflows")
    end

    {:ok,
     socket
     |> assign(:current_page, :workflows)
     |> assign(:current_section, :management)
     |> assign(:sidebar_collapsed, false)
     |> assign(:page_title, "Agent Workflows")
     |> assign(:view_mode, :list)
     |> assign(:selected_workflow, nil)
     |> load_workflows_data()}
  end

  @impl true
  def handle_event("toggle_sidebar", _params, socket) do
    {:noreply, assign(socket, :sidebar_collapsed, !socket.assigns.sidebar_collapsed)}
  end

  @impl true
  def handle_event("view_workflow", %{"workflow_id" => workflow_id}, socket) do
    workflow = Enum.find(socket.assigns.workflows, &(&1.id == workflow_id))

    {:noreply,
     socket
     |> assign(:selected_workflow, workflow)
     |> assign(:view_mode, :detail)}
  end

  @impl true
  def handle_event("back_to_list", _params, socket) do
    {:noreply,
     socket
     |> assign(:view_mode, :list)
     |> assign(:selected_workflow, nil)}
  end

  @impl true
  def handle_event("execute_workflow", %{"workflow_id" => _workflow_id}, socket) do
    # TODO: Implement workflow execution
    {:noreply, put_flash(socket, :info, "Workflow execution started")}
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
          Agent Workflows
          <:subtitle>Manage agent execution workflows, step definitions, and monitoring</:subtitle>

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
        <.workflows_list workflows={@workflows} workflow_stats={@workflow_stats} />
      </div>

      <div :if={@view_mode == :detail && @selected_workflow}>
        <.workflow_detail workflow={@selected_workflow} />
      </div>
    </AdminLayouts.admin>
    """
  end

  defp load_workflows_data(socket) do
    AdminErrorHandler.handle_data_loading(socket, :workflows, fn ->
      # Load actual workflows from the registry
      workflow_ids = Registry.list_workflows()

      workflows =
        workflow_ids
        |> Enum.map(fn workflow_id ->
          case Registry.get_workflow(workflow_id) do
            {:ok, spec} -> convert_workflow_spec_to_ui_format(spec)
            {:error, _} -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)

      workflow_stats = calculate_workflow_stats(workflows)

      %{
        workflows: workflows,
        workflow_stats: workflow_stats
      }
    end)
    |> case do
      %{workflows: data} when is_map(data) ->
        socket
        |> assign(:workflows, data.workflows)
        |> assign(:workflow_stats, data.workflow_stats)

      socket ->
        # Error case - use fallback data
        socket
        |> assign(:workflows, [])
        |> assign(:workflow_stats, %{
          total: 0,
          active: 0,
          inactive: 0,
          draft: 0,
          by_category: %{},
          avg_success_rate: 0.0
        })
    end
  end

  # defp get_mock_workflows do
  #   [
  #     %{
  #       id: "workflow_001",
  #       name: "Code Analysis & Review",
  #       description: "Automated code analysis with review generation and suggestions",
  #       status: "active",
  #       created_at: "2024-01-15",
  #       last_run: "2 hours ago",
  #       total_runs: 45,
  #       success_rate: "97.8%",
  #       category: "development",
  #       trigger: "manual",
  #       avg_duration: "3.2 min",
  #       tools_used: ["file_reader", "code_analyzer", "llm_reviewer"],
  #       steps: [
  #         %{
  #           name: "Parse Repository Structure",
  #           status: "completed",
  #           type: "tool_call",
  #           tool: "file_reader"
  #         },
  #         %{
  #           name: "Analyze Code Quality",
  #           status: "completed",
  #           type: "tool_call",
  #           tool: "code_analyzer"
  #         },
  #         %{
  #           name: "Generate Review Comments",
  #           status: "completed",
  #           type: "llm_call",
  #           model: "gpt-4"
  #         },
  #         %{
  #           name: "Create Summary Report",
  #           status: "completed",
  #           type: "decision_point",
  #           condition: "quality_score > 7"
  #         }
  #       ]
  #     },
  #     %{
  #       id: "workflow_002",
  #       name: "Bug Investigation & Fix",
  #       description: "Systematic bug investigation with automated fix suggestions",
  #       status: "active",
  #       created_at: "2024-01-10",
  #       last_run: "12 hours ago",
  #       total_runs: 156,
  #       success_rate: "99.4%",
  #       category: "debugging",
  #       trigger: "error_detected",
  #       avg_duration: "5.7 min",
  #       tools_used: ["error_tracker", "log_analyzer", "test_runner", "code_fixer"],
  #       steps: [
  #         %{
  #           name: "Collect Error Context",
  #           status: "completed",
  #           type: "tool_call",
  #           tool: "error_tracker"
  #         },
  #         %{
  #           name: "Analyze Stack Trace",
  #           status: "completed",
  #           type: "tool_call",
  #           tool: "log_analyzer"
  #         },
  #         %{
  #           name: "Run Related Tests",
  #           status: "completed",
  #           type: "tool_call",
  #           tool: "test_runner"
  #         },
  #         %{
  #           name: "Generate Fix Suggestions",
  #           status: "completed",
  #           type: "llm_call",
  #           model: "claude-3"
  #         },
  #         %{
  #           name: "Apply Automated Fixes",
  #           status: "completed",
  #           type: "decision_point",
  #           condition: "confidence > 0.8"
  #         }
  #       ]
  #     },
  #     %{
  #       id: "workflow_003",
  #       name: "Documentation Generation",
  #       description: "Automated documentation generation from code and comments",
  #       status: "inactive",
  #       created_at: "2024-01-08",
  #       last_run: "3 days ago",
  #       total_runs: 23,
  #       success_rate: "91.3%",
  #       category: "documentation",
  #       trigger: "scheduled",
  #       avg_duration: "2.1 min",
  #       tools_used: ["code_parser", "doc_generator", "markdown_formatter"],
  #       steps: [
  #         %{
  #           name: "Extract Code Structure",
  #           status: "completed",
  #           type: "tool_call",
  #           tool: "code_parser"
  #         },
  #         %{
  #           name: "Generate API Docs",
  #           status: "completed",
  #           type: "llm_call",
  #           model: "gpt-3.5-turbo"
  #         },
  #         %{
  #           name: "Format Documentation",
  #           status: "completed",
  #           type: "tool_call",
  #           tool: "markdown_formatter"
  #         },
  #         %{name: "Update README", status: "failed", type: "tool_call", tool: "file_writer"}
  #       ]
  #     },
  #     %{
  #       id: "workflow_004",
  #       name: "Test Suite Optimization",
  #       description: "Analyze and optimize test suite performance and coverage",
  #       status: "running",
  #       created_at: "2024-01-20",
  #       last_run: "30 minutes ago",
  #       total_runs: 8,
  #       success_rate: "87.5%",
  #       category: "testing",
  #       trigger: "manual",
  #       avg_duration: "8.3 min",
  #       tools_used: ["test_analyzer", "coverage_reporter", "performance_profiler"],
  #       steps: [
  #         %{
  #           name: "Analyze Test Coverage",
  #           status: "completed",
  #           type: "tool_call",
  #           tool: "test_analyzer"
  #         },
  #         %{
  #           name: "Identify Slow Tests",
  #           status: "running",
  #           type: "tool_call",
  #           tool: "performance_profiler"
  #         },
  #         %{
  #           name: "Generate Optimization Plan",
  #           status: "pending",
  #           type: "llm_call",
  #           model: "gpt-4"
  #         },
  #         %{
  #           name: "Apply Optimizations",
  #           status: "pending",
  #           type: "decision_point",
  #           condition: "user_approval"
  #         }
  #       ]
  #     }
  #   ]
  # end

  # Convert WorkflowEngine.Spec to UI format
  defp convert_workflow_spec_to_ui_format(%AgentCore.WorkflowEngine.Spec{} = spec) do
    # Calculate basic stats from the spec
    total_steps = map_size(spec.nodes)

    # Determine status based on spec properties
    status = if spec.version > 0, do: "active", else: "draft"

    # Extract step types for tools_used
    tools_used =
      spec.nodes
      |> Enum.map(fn {_node_id, node} ->
        case node.step do
          module when is_atom(module) ->
            module |> to_string() |> String.split(".") |> List.last() |> String.downcase()

          _ ->
            "unknown"
        end
      end)
      |> Enum.uniq()

    %{
      id: to_string(spec.id),
      name: format_workflow_name(spec.id),
      description: "Workflow with #{total_steps} steps",
      status: status,
      # TODO: Add created_at to spec
      created_at: format_datetime(nil),
      # TODO: Get from actual execution tracking
      last_run: "Never",
      # TODO: Get from actual execution tracking
      total_runs: 0,
      # TODO: Get from actual execution tracking
      success_rate: "100.0%",
      category: determine_workflow_category(spec.id),
      # TODO: Determine from spec
      trigger: "manual",
      # TODO: Get from actual execution tracking
      avg_duration: "N/A",
      tools_used: tools_used,
      steps: convert_workflow_steps(spec.nodes)
    }
  end

  defp format_workflow_name(workflow_id) do
    workflow_id
    |> to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp determine_workflow_category(workflow_id) do
    workflow_str = to_string(workflow_id)

    cond do
      String.contains?(workflow_str, "rag") -> "development"
      String.contains?(workflow_str, "history") -> "development"
      String.contains?(workflow_str, "test") -> "testing"
      String.contains?(workflow_str, "debug") -> "debugging"
      String.contains?(workflow_str, "doc") -> "documentation"
      true -> "general"
    end
  end

  defp convert_workflow_steps(nodes) do
    nodes
    |> Enum.map(fn {node_id, node} ->
      %{
        name: format_step_name(node_id),
        # Default status
        status: "completed",
        type: determine_step_type(node.step),
        tool: extract_tool_name(node.step)
      }
    end)
  end

  defp format_step_name(node_id) do
    node_id
    |> to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp determine_step_type(step_module) when is_atom(step_module) do
    module_name = to_string(step_module)

    cond do
      String.contains?(module_name, "Llm") -> "llm_call"
      String.contains?(module_name, "Tool") -> "tool_call"
      String.contains?(module_name, "Decision") -> "decision_point"
      true -> "tool_call"
    end
  end

  defp determine_step_type(_), do: "tool_call"

  defp extract_tool_name(step_module) when is_atom(step_module) do
    step_module
    |> to_string()
    |> String.split(".")
    |> List.last()
    |> String.downcase()
  end

  defp extract_tool_name(_), do: "unknown"

  # Helper function to format datetime
  defp format_datetime(nil), do: "Never"

  defp format_datetime(datetime) do
    case DateTime.from_naive(datetime, "Etc/UTC") do
      {:ok, dt} -> Calendar.strftime(dt, "%Y-%m-%d")
      _ -> "Unknown"
    end
  end

  defp calculate_workflow_stats(workflows) do
    %{
      total: length(workflows),
      active: Enum.count(workflows, &(&1.status == "active")),
      inactive: Enum.count(workflows, &(&1.status == "inactive")),
      draft: Enum.count(workflows, &(&1.status == "draft")),
      by_category:
        workflows
        |> Enum.group_by(& &1.category)
        |> Enum.map(fn {k, v} -> {k, length(v)} end)
        |> Enum.into(%{}),
      avg_success_rate:
        if length(workflows) > 0 do
          workflows
          |> Enum.map(fn workflow ->
            case Float.parse(String.replace(workflow.success_rate, "%", "")) do
              {rate, _} -> rate
              :error -> 100.0
            end
          end)
          |> Enum.sum()
          |> Kernel./(length(workflows))
          |> Float.round(1)
        else
          0.0
        end
    }
  end

  attr :workflows, :list, required: true
  attr :workflow_stats, :map, required: true

  defp workflows_list(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="grid grid-cols-1 md:grid-cols-4 gap-4">
        <.stat_card title="Total Workflows" value={@workflow_stats.total} color="primary" />
        <.stat_card title="Active" value={@workflow_stats.active} color="success" />
        <.stat_card title="Draft" value={@workflow_stats.draft} color="warning" />
        <.stat_card title="Inactive" value={@workflow_stats.inactive} color="info" />
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mb-6">
        <div class="card bg-base-200 shadow-sm">
          <div class="card-body p-4">
            <h4 class="font-semibold mb-3">Workflows by Category</h4>

            <div class="space-y-2">
              <div
                :for={{category, count} <- @workflow_stats.by_category}
                class="flex justify-between"
              >
                <span class="capitalize text-sm">{category}</span>
                <span class="badge badge-outline badge-sm">{count}</span>
              </div>
            </div>
          </div>
        </div>

        <div class="card bg-base-200 shadow-sm">
          <div class="card-body p-4">
            <h4 class="font-semibold mb-3">Quick Actions</h4>

            <div class="space-y-2">
              <button class="btn btn-outline btn-sm w-full justify-start">
                <.icon name="hero-plus" class="size-4 mr-2" /> Create New Workflow
              </button>
              <button class="btn btn-outline btn-sm w-full justify-start">
                <.icon name="hero-document-duplicate" class="size-4 mr-2" /> Import Template
              </button>
            </div>
          </div>
        </div>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <.workflow_card :for={workflow <- @workflows} workflow={workflow} />
      </div>
    </div>
    """
  end

  attr :workflow, :map, required: true

  defp workflow_card(assigns) do
    ~H"""
    <div class="card bg-base-200 shadow-sm hover:shadow-md transition-shadow">
      <div class="card-body">
        <div class="flex justify-between items-start">
          <div class="flex-1">
            <div class="flex items-center gap-2 mb-1">
              <h3 class="card-title text-base">{@workflow.name}</h3>
              <.workflow_category_badge category={@workflow.category} />
            </div>

            <p class="text-sm text-base-content/70 mb-2">{@workflow.description}</p>

            <div class="flex gap-2 mb-3">
              <.workflow_status_badge status={@workflow.status} />
              <.workflow_trigger_badge trigger={@workflow.trigger} />
            </div>

            <div class="flex flex-wrap gap-1 mb-2">
              <span
                :for={tool <- Enum.take(@workflow.tools_used, 3)}
                class="badge badge-xs badge-ghost"
              >
                {tool}
              </span>
              <span :if={length(@workflow.tools_used) > 3} class="badge badge-xs badge-ghost">
                +{length(@workflow.tools_used) - 3} more
              </span>
            </div>
          </div>

          <div class="dropdown dropdown-end">
            <div tabindex="0" role="button" class="btn btn-ghost btn-sm">
              <.icon name="hero-ellipsis-vertical" class="size-4" />
            </div>

            <ul class="dropdown-content menu bg-base-100 rounded-box z-[1] w-52 p-2 shadow">
              <li>
                <button phx-click="view_workflow" phx-value-workflow_id={@workflow.id}>
                  <.icon name="hero-eye" class="size-4" /> View Details
                </button>
              </li>

              <li>
                <button phx-click="execute_workflow" phx-value-workflow_id={@workflow.id}>
                  <.icon name="hero-play" class="size-4" /> Execute Now
                </button>
              </li>
            </ul>
          </div>
        </div>

        <div class="mt-4 grid grid-cols-2 gap-4 text-sm">
          <div>
            <span class="text-base-content/70">Last Run:</span>
            <div class="font-medium">{@workflow.last_run}</div>
          </div>

          <div>
            <span class="text-base-content/70">Success Rate:</span>
            <div class="font-medium text-success">{@workflow.success_rate}</div>
          </div>

          <div>
            <span class="text-base-content/70">Total Runs:</span>
            <div class="font-medium">{@workflow.total_runs}</div>
          </div>

          <div>
            <span class="text-base-content/70">Avg Duration:</span>
            <div class="font-medium">{@workflow.avg_duration}</div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :workflow, :map, required: true

  defp workflow_detail(assigns) do
    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
      <div class="lg:col-span-2 space-y-6">
        <div class="card bg-base-200 shadow-sm">
          <div class="card-body">
            <div class="flex justify-between items-start mb-4">
              <div>
                <div class="flex items-center gap-2 mb-2">
                  <h3 class="text-xl font-semibold">{@workflow.name}</h3>
                  <.workflow_category_badge category={@workflow.category} />
                </div>

                <p class="text-base-content/70 mb-3">{@workflow.description}</p>

                <div class="flex gap-2">
                  <.workflow_status_badge status={@workflow.status} />
                  <.workflow_trigger_badge trigger={@workflow.trigger} />
                </div>
              </div>

              <button
                class="btn btn-primary btn-sm"
                phx-click="execute_workflow"
                phx-value-workflow_id={@workflow.id}
              >
                <.icon name="hero-play" class="size-4 mr-2" /> Execute
              </button>
            </div>

            <div class="grid grid-cols-2 md:grid-cols-4 gap-4 p-4 bg-base-100 rounded-lg">
              <div class="text-center">
                <div class="text-lg font-bold text-primary">{@workflow.total_runs}</div>

                <div class="text-xs text-base-content/70">Total Runs</div>
              </div>

              <div class="text-center">
                <div class="text-lg font-bold text-success">{@workflow.success_rate}</div>

                <div class="text-xs text-base-content/70">Success Rate</div>
              </div>

              <div class="text-center">
                <div class="text-lg font-bold text-info">{@workflow.avg_duration}</div>

                <div class="text-xs text-base-content/70">Avg Duration</div>
              </div>

              <div class="text-center">
                <div class="text-lg font-bold text-warning">{length(@workflow.tools_used)}</div>

                <div class="text-xs text-base-content/70">Tools Used</div>
              </div>
            </div>
          </div>
        </div>

        <div class="card bg-base-200 shadow-sm">
          <div class="card-body">
            <h4 class="card-title mb-4">Workflow Steps</h4>

            <div class="space-y-3">
              <div
                :for={{step, index} <- Enum.with_index(@workflow.steps)}
                class="flex items-start gap-3 p-4 bg-base-100 rounded-lg"
              >
                <div class="flex-shrink-0">
                  <div class="w-8 h-8 rounded-full bg-primary text-primary-content flex items-center justify-center text-sm font-medium">
                    {index + 1}
                  </div>
                </div>

                <div class="flex-1">
                  <div class="flex items-center gap-2 mb-1">
                    <p class="font-medium">{step.name}</p>
                    <.step_type_badge type={step.type} />
                  </div>

                  <div class="text-sm text-base-content/70">
                    <%= case step.type do %>
                      <% "tool_call" -> %>
                        Tool:
                        <span class="font-mono text-xs bg-base-200 px-1 rounded">{step.tool}</span>
                      <% "llm_call" -> %>
                        Model:
                        <span class="font-mono text-xs bg-base-200 px-1 rounded">{step.model}</span>
                      <% "decision_point" -> %>
                        Condition:
                        <span class="font-mono text-xs bg-base-200 px-1 rounded">
                          {step.condition}
                        </span>
                      <% _ -> %>
                        <span>Standard execution step</span>
                    <% end %>
                  </div>
                </div>

                <div><.step_status_badge status={step.status} /></div>
              </div>
            </div>
          </div>
        </div>

        <div class="card bg-base-200 shadow-sm">
          <div class="card-body">
            <h4 class="card-title mb-4">Tools & Dependencies</h4>

            <div class="grid grid-cols-2 md:grid-cols-3 gap-2">
              <div
                :for={tool <- @workflow.tools_used}
                class="flex items-center gap-2 p-2 bg-base-100 rounded"
              >
                <.icon name="hero-wrench-screwdriver" class="size-4 text-primary" />
                <span class="text-sm font-mono">{tool}</span>
              </div>
            </div>
          </div>
        </div>
      </div>

      <div class="space-y-6">
        <div class="card bg-base-200 shadow-sm">
          <div class="card-body">
            <h4 class="card-title">Workflow Info</h4>

            <div class="space-y-3">
              <div>
                <p class="text-sm text-base-content/70">Category</p>

                <p class="font-medium capitalize">{@workflow.category}</p>
              </div>

              <div>
                <p class="text-sm text-base-content/70">Trigger Type</p>

                <p class="font-medium capitalize">{@workflow.trigger}</p>
              </div>

              <div>
                <p class="text-sm text-base-content/70">Created</p>

                <p class="font-medium">{@workflow.created_at}</p>
              </div>

              <div>
                <p class="text-sm text-base-content/70">Last Run</p>

                <p class="font-medium">{@workflow.last_run}</p>
              </div>
            </div>
          </div>
        </div>

        <div class="card bg-base-200 shadow-sm">
          <div class="card-body">
            <h4 class="card-title">Actions</h4>

            <div class="space-y-2">
              <button class="btn btn-primary btn-sm w-full">
                <.icon name="hero-play" class="size-4 mr-2" /> Execute Now
              </button>
              <button class="btn btn-outline btn-sm w-full">
                <.icon name="hero-pencil" class="size-4 mr-2" /> Edit Workflow
              </button>
              <button class="btn btn-outline btn-sm w-full">
                <.icon name="hero-document-duplicate" class="size-4 mr-2" /> Duplicate
              </button>
              <button class="btn btn-outline btn-error btn-sm w-full">
                <.icon name="hero-trash" class="size-4 mr-2" /> Delete
              </button>
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

  defp workflow_status_badge(assigns) do
    {badge_class, icon} =
      case assigns.status do
        "active" -> {"badge-success", "hero-check-circle"}
        "inactive" -> {"badge-error", "hero-x-circle"}
        "running" -> {"badge-warning", "hero-play"}
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

  attr :status, :string, required: true

  defp step_status_badge(assigns) do
    {badge_class, icon} =
      case assigns.status do
        "completed" -> {"badge-success", "hero-check"}
        "running" -> {"badge-warning", "hero-play"}
        "failed" -> {"badge-error", "hero-x-mark"}
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

  attr :category, :string, required: true

  defp workflow_category_badge(assigns) do
    {badge_class, icon} =
      case assigns.category do
        "development" -> {"badge-primary", "hero-code-bracket"}
        "debugging" -> {"badge-error", "hero-bug-ant"}
        "documentation" -> {"badge-info", "hero-document-text"}
        "testing" -> {"badge-success", "hero-beaker"}
        "deployment" -> {"badge-warning", "hero-rocket-launch"}
        _ -> {"badge-ghost", "hero-cog-6-tooth"}
      end

    assigns = assign(assigns, :badge_class, badge_class)
    assigns = assign(assigns, :icon, icon)

    ~H"""
    <div class={["badge badge-xs gap-1", @badge_class]}>
      <.icon name={@icon} class="size-2" /> {String.capitalize(@category)}
    </div>
    """
  end

  attr :trigger, :string, required: true

  defp workflow_trigger_badge(assigns) do
    {badge_class, icon} =
      case assigns.trigger do
        "manual" -> {"badge-outline", "hero-hand-raised"}
        "scheduled" -> {"badge-outline badge-info", "hero-clock"}
        "error_detected" -> {"badge-outline badge-error", "hero-exclamation-triangle"}
        "webhook" -> {"badge-outline badge-warning", "hero-link"}
        _ -> {"badge-outline", "hero-bolt"}
      end

    assigns = assign(assigns, :badge_class, badge_class)
    assigns = assign(assigns, :icon, icon)

    ~H"""
    <div class={["badge badge-xs gap-1", @badge_class]}>
      <.icon name={@icon} class="size-2" /> {String.capitalize(@trigger)}
    </div>
    """
  end

  attr :type, :string, required: true

  defp step_type_badge(assigns) do
    {badge_class, icon} =
      case assigns.type do
        "tool_call" -> {"badge-primary badge-outline", "hero-wrench-screwdriver"}
        "llm_call" -> {"badge-secondary badge-outline", "hero-cpu-chip"}
        "decision_point" -> {"badge-warning badge-outline", "hero-arrow-path"}
        _ -> {"badge-ghost", "hero-cog-6-tooth"}
      end

    assigns = assign(assigns, :badge_class, badge_class)
    assigns = assign(assigns, :icon, icon)

    ~H"""
    <div class={["badge badge-xs gap-1", @badge_class]}>
      <.icon name={@icon} class="size-2" /> {String.replace(@type, "_", " ") |> String.capitalize()}
    </div>
    """
  end
end
