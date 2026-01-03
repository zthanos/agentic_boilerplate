defmodule AgentWebWeb.WorkflowGraphComponent do
  @moduledoc """
  A LiveView component for visualizing workflow execution graphs.

  This component renders workflow specifications as interactive SVG graphs,
  showing nodes, edges, and real-time execution status. It supports:

  - Node visualization with status-based coloring
  - Edge connections between workflow steps
  - Hover tooltips with step details
  - Real-time status updates during execution
  """

  use AgentWebWeb, :live_component

  @doc """
  Renders the workflow graph visualization.

  ## Assigns

  - `workflow_spec` - The workflow specification to visualize
  - `execution_state` - Current execution status of each node (map of node_id => %{status: :pending/:running/:completed/:failed, execution_time_ms: integer, error: string})
  - `current_step` - Currently executing step (highlighted)
  - `class` - Additional CSS classes for the container
  """
  def render(assigns) do
    assigns = assign_defaults(assigns)

    ~H"""
    <div class={["workflow-graph-container", @class]} id={"workflow-graph-#{@id}"}>
      <%= if @workflow_spec do %>
        <svg
          class="workflow-graph-svg w-full h-full"
          viewBox="0 0 800 600"
          xmlns="http://www.w3.org/2000/svg"
        >
          <!-- Background -->
          <rect width="800" height="600" fill="transparent" />
          <!-- Arrow marker definition (only once per SVG) -->
          <defs>
            <marker
              id={"arrowhead-#{@id}"}
              markerWidth="10"
              markerHeight="7"
              refX="9"
              refY="3.5"
              orient="auto"
            >
              <polygon
                points="0 0, 10 3.5, 0 7"
                fill="currentColor"
                class="text-base-content/30"
              />
            </marker>
          </defs>
          <!-- Edges (render first so they appear behind nodes) -->
          <%= for edge <- @edges do %>
            <.workflow_edge edge={edge} marker_id={"arrowhead-#{@id}"} />
          <% end %>
          <!-- Nodes -->
          <%= for node <- @nodes do %>
            <.workflow_node
              node={node}
              current_step={@current_step}
              execution_state={@execution_state}
              workflow_spec={@workflow_spec}
            />
          <% end %>
        </svg>
        <!-- Execution Progress Summary -->
        <%= if has_execution_progress?(@execution_state) do %>
          <div class="mt-4 p-3 bg-base-100 rounded-lg border border-base-300">
            <div class="flex items-center justify-between text-sm">
              <span class="font-medium">Execution Progress</span>
              <span class="text-base-content/70">
                {count_completed_nodes(@execution_state)}/{map_size(@workflow_spec.nodes)} steps
              </span>
            </div>

            <div class="mt-2">
              <div class="w-full bg-base-300 rounded-full h-2">
                <div
                  class="bg-primary h-2 rounded-full transition-all duration-300"
                  style={"width: #{calculate_progress_percentage(@execution_state, @workflow_spec)}%"}
                >
                </div>
              </div>
            </div>

            <%= if get_current_executing_step(@execution_state) do %>
              <div class="mt-2 text-xs text-base-content/70">
                Currently executing:
                <span class="font-medium">{get_current_executing_step(@execution_state)}</span>
              </div>
            <% end %>
          </div>
        <% end %>
        <!-- Tooltips -->
        <div class="workflow-tooltips">
          <%= for node <- @nodes do %>
            <div
              id={"tooltip-#{node.id}"}
              class="tooltip hidden absolute z-10 bg-base-300 text-base-content p-2 rounded shadow-lg border border-base-content/20 max-w-xs"
            >
              <div class="font-semibold">
                {node.name}
                <%= if is_entry_node?(node, @workflow_spec) do %>
                  <span class="text-success text-xs ml-1">(START)</span>
                <% end %>

                <%= if is_exit_node?(node, @workflow_spec) do %>
                  <span class="text-error text-xs ml-1">(END)</span>
                <% end %>
              </div>

              <div class="text-sm text-base-content/70 mt-1">
                Status: <span class="font-medium">{get_node_status(node, @execution_state)}</span>
              </div>

              <%= if get_execution_time(node, @execution_state) do %>
                <div class="text-sm text-base-content/70">
                  Execution time: {get_execution_time(node, @execution_state)}ms
                </div>
              <% end %>

              <%= if get_node_error(node, @execution_state) do %>
                <div class="text-sm text-error mt-1">
                  Error: {get_node_error(node, @execution_state)}
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      <% else %>
        <div class="flex items-center justify-center h-64 bg-base-300 rounded-lg">
          <div class="text-center text-base-content/50">
            <div class="text-lg font-semibold mb-2">No Workflow Loaded</div>

            <div class="text-sm">Select an agent to view its workflow graph</div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # Workflow edge component
  defp workflow_edge(assigns) do
    ~H"""
    <g class="workflow-edge">
      <line
        x1={@edge.x1}
        y1={@edge.y1}
        x2={@edge.x2}
        y2={@edge.y2}
        stroke="currentColor"
        stroke-width="2"
        class="text-base-content/30"
        marker-end={"url(##{@marker_id})"}
      />
    </g>
    """
  end

  # Workflow node component
  defp workflow_node(assigns) do
    node_class = get_node_class(assigns.node, assigns.current_step, assigns.execution_state)
    is_entry = is_entry_node?(assigns.node, assigns.workflow_spec)
    is_exit = is_exit_node?(assigns.node, assigns.workflow_spec)
    node_status = get_node_status(assigns.node, assigns.execution_state)
    execution_time = get_execution_time(assigns.node, assigns.execution_state)

    assigns = assign(assigns, :node_class, node_class)
    assigns = assign(assigns, :is_entry, is_entry)
    assigns = assign(assigns, :is_exit, is_exit)
    assigns = assign(assigns, :node_status, node_status)
    assigns = assign(assigns, :execution_time, execution_time)

    ~H"""
    <g
      class="workflow-node cursor-pointer"
      phx-hook="WorkflowNodeTooltip"
      data-node-id={@node.id}
      id={"workflow-node-#{@node.id}"}
    >
      <!-- Node shape - different shapes for start/end nodes -->
      <%= if @is_entry do %>
        <!-- Start node - diamond shape -->
        <polygon
          points={"#{@node.x},#{@node.y - 35} #{@node.x + 35},#{@node.y} #{@node.x},#{@node.y + 35} #{@node.x - 35},#{@node.y}"}
          class={@node_class}
          stroke="currentColor"
          stroke-width="3"
        />
        <!-- Start indicator -->
        <text
          x={@node.x}
          y={@node.y - 45}
          text-anchor="middle"
          class="text-xs font-bold fill-success"
        >
          START
        </text>
      <% else %>
        <%= if @is_exit do %>
          <!-- End node - square shape -->
          <rect
            x={@node.x - 30}
            y={@node.y - 30}
            width="60"
            height="60"
            class={@node_class}
            stroke="currentColor"
            stroke-width="3"
            rx="5"
          />
          <!-- End indicator -->
          <text
            x={@node.x}
            y={@node.y - 45}
            text-anchor="middle"
            class="text-xs font-bold fill-error"
          >
            END
          </text>
        <% else %>
          <!-- Regular node - circle shape -->
          <circle
            cx={@node.x}
            cy={@node.y}
            r="30"
            class={@node_class}
            stroke="currentColor"
            stroke-width="2"
          />
        <% end %>
      <% end %>
      <!-- Node label -->
      <text
        x={@node.x}
        y={@node.y + 5}
        text-anchor="middle"
        class="text-sm font-medium fill-current pointer-events-none"
      >
        {@node.display_name}
      </text>
      <!-- Status indicators -->
      <%= cond do %>
        <% @node_status == :running -> %>
          <!-- Running indicator with pulsing animation -->
          <circle
            cx={@node.x + 20}
            cy={@node.y - 20}
            r="8"
            class="fill-warning animate-pulse"
          />
          <text
            x={@node.x + 20}
            y={@node.y - 16}
            text-anchor="middle"
            class="text-xs font-bold fill-warning-content pointer-events-none"
          >
            ▶
          </text>
        <% @node_status == :completed -> %>
          <!-- Completed indicator -->
          <circle
            cx={@node.x + 20}
            cy={@node.y - 20}
            r="8"
            class="fill-success"
          />
          <text
            x={@node.x + 20}
            y={@node.y - 16}
            text-anchor="middle"
            class="text-xs font-bold fill-success-content pointer-events-none"
          >
            ✓
          </text>

          <%= if @execution_time do %>
            <text
              x={@node.x}
              y={@node.y + 45}
              text-anchor="middle"
              class="text-xs fill-success pointer-events-none"
            >
              {@execution_time}ms
            </text>
          <% end %>
        <% @node_status == :failed -> %>
          <!-- Failed indicator -->
          <circle
            cx={@node.x + 20}
            cy={@node.y - 20}
            r="8"
            class="fill-error"
          />
          <text
            x={@node.x + 20}
            y={@node.y - 16}
            text-anchor="middle"
            class="text-xs font-bold fill-error-content pointer-events-none"
          >
            ✗
          </text>
        <% @node.id == @current_step -> %>
          <!-- Current step indicator (fallback) -->
          <circle
            cx={@node.x + 20}
            cy={@node.y - 20}
            r="8"
            class="fill-primary animate-pulse"
          />
          <text
            x={@node.x + 20}
            y={@node.y - 16}
            text-anchor="middle"
            class="text-xs font-bold fill-primary-content pointer-events-none"
          >
            ▶
          </text>
        <% true -> %>
          <!-- No special indicator for pending nodes -->
      <% end %>
    </g>
    """
  end

  # Private helper functions

  defp assign_defaults(assigns) do
    assigns
    |> assign_new(:class, fn -> "" end)
    |> assign_new(:current_step, fn -> nil end)
    |> assign_new(:execution_state, fn -> %{} end)
    |> assign_new(:id, fn -> "default" end)
    |> compute_layout()
  end

  defp compute_layout(%{workflow_spec: nil} = assigns) do
    assigns
    |> assign(:nodes, [])
    |> assign(:edges, [])
  end

  defp compute_layout(%{workflow_spec: workflow_spec} = assigns) do
    nodes = compute_node_positions(workflow_spec)
    edges = compute_edge_positions(workflow_spec, nodes)

    assigns
    |> assign(:nodes, nodes)
    |> assign(:edges, edges)
  end

  defp compute_node_positions(workflow_spec) do
    node_ids = Map.keys(workflow_spec.nodes)
    node_count = length(node_ids)

    # Simple circular layout for now
    # TODO: Implement more sophisticated layout algorithms
    center_x = 400
    center_y = 300
    radius = min(150, max(80, node_count * 15))

    node_ids
    |> Enum.with_index()
    |> Enum.map(fn {node_id, index} ->
      angle = 2 * :math.pi() * index / node_count
      x = center_x + radius * :math.cos(angle)
      y = center_y + radius * :math.sin(angle)

      %{
        id: node_id,
        name: to_string(node_id),
        display_name: format_node_name(node_id),
        x: x,
        y: y
      }
    end)
  end

  defp compute_edge_positions(workflow_spec, nodes) do
    node_positions = Map.new(nodes, fn node -> {node.id, {node.x, node.y}} end)

    workflow_spec.edges
    |> Enum.map(fn edge ->
      {x1, y1} = Map.get(node_positions, edge.from, {0, 0})
      {x2, y2} = Map.get(node_positions, edge.to, {0, 0})

      %{
        from: edge.from,
        to: edge.to,
        x1: x1,
        y1: y1,
        x2: x2,
        y2: y2,
        condition: Map.get(edge, :when)
      }
    end)
  end

  defp format_node_name(node_id) do
    node_id
    |> to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
    # Limit length for display
    |> String.slice(0, 10)
  end

  defp get_node_class(node, current_step, execution_state) do
    status = get_node_status(node, execution_state)
    is_current = node.id == current_step

    base_classes = "transition-colors duration-200"

    status_class =
      case status do
        :pending -> "fill-base-200 text-base-content/50"
        :running -> "fill-warning text-warning-content"
        :completed -> "fill-success text-success-content"
        :failed -> "fill-error text-error-content"
        _ -> "fill-base-200 text-base-content/50"
      end

    current_class = if is_current, do: "ring-4 ring-primary ring-opacity-50", else: ""

    [base_classes, status_class, current_class]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
  end

  defp get_node_status(node, execution_state) do
    case Map.get(execution_state, node.id) do
      %{status: status} -> status
      _ -> :pending
    end
  end

  defp get_execution_time(node, execution_state) do
    case Map.get(execution_state, node.id) do
      %{execution_time_ms: time} when is_integer(time) -> time
      _ -> nil
    end
  end

  defp get_node_error(node, execution_state) do
    case Map.get(execution_state, node.id) do
      %{error: error} when is_binary(error) -> error
      _ -> nil
    end
  end

  defp is_entry_node?(node, workflow_spec) do
    case workflow_spec do
      %{entry: entry} -> node.id == entry
      _ -> false
    end
  end

  defp is_exit_node?(node, workflow_spec) do
    case workflow_spec do
      %{exits: exits} when is_list(exits) -> node.id in exits
      _ -> false
    end
  end

  defp has_execution_progress?(execution_state) do
    execution_state != %{} and map_size(execution_state) > 0
  end

  defp count_completed_nodes(execution_state) do
    execution_state
    |> Enum.count(fn {_node_id, state} ->
      Map.get(state, :status) == :completed
    end)
  end

  defp calculate_progress_percentage(execution_state, workflow_spec) do
    total_nodes = map_size(workflow_spec.nodes)
    completed_nodes = count_completed_nodes(execution_state)

    if total_nodes > 0 do
      round(completed_nodes / total_nodes * 100)
    else
      0
    end
  end

  defp get_current_executing_step(execution_state) do
    case Enum.find(execution_state, fn {_node_id, state} ->
           Map.get(state, :status) == :running
         end) do
      {node_id, _state} -> format_node_name(node_id)
      nil -> nil
    end
  end
end
