defmodule AgentWebWeb.AdminSidebar do
  @moduledoc """
  Admin sidebar LiveComponent with organized navigation sections.

  This component is stateless - it receives `collapsed` from the parent LiveView
  and sends toggle events back to the parent via `handle_info/2`.
  """
  use AgentWebWeb, :live_component
  import AgentWebWeb.AdminAccessibility

  @navigation_sections %{
    analytics: [
      %{key: :dashboard, label: "Dashboard", href: "/admin/dashboard", icon: "hero-chart-bar"},
      %{key: :runs, label: "Run History", href: "/admin/runs", icon: "hero-clock"}
    ],
    operations: [
      %{key: :chat, label: "Chat", href: "/admin/chat", icon: "hero-chat-bubble-left-right"}
    ],
    management: [
      %{key: :settings, label: "Settings", href: "/admin/settings", icon: "hero-cog-6-tooth"},
      %{key: :profiles, label: "Profiles", href: "/admin/profiles", icon: "hero-users"},
      %{key: :agents, label: "Agents", href: "/admin/agents", icon: "hero-cpu-chip"},
      %{key: :workflows, label: "Workflows", href: "/admin/workflows", icon: "hero-squares-2x2"},
      %{key: :testing, label: "Testing", href: "/admin/testing", icon: "hero-beaker"}
    ]
  }

  @impl true
  def update(assigns, socket) do
    breadcrumbs = generate_breadcrumbs(assigns[:current_page])
    is_mobile? = assigns[:is_mobile?] || assigns[:is_mobile] || false

    # Το collapsed state έρχεται ΠΑΝΤΑ από το parent
    # Δεν το ορίζουμε ποτέ εδώ - μόνο το διαβάζουμε από τα assigns
    {:ok,
     socket
     |> assign(assigns)  # Αυτό περιλαμβάνει το :collapsed από το parent
     |> assign(:breadcrumbs, breadcrumbs)
     |> assign(:navigation_sections, @navigation_sections)
     |> assign(:is_mobile?, is_mobile?)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="relative">
      <!-- Mobile Overlay -->
      <div
        :if={!@collapsed && @is_mobile?}
        class="fixed inset-0 bg-black/50 z-40 lg:hidden"
        phx-click="toggle_sidebar"
        phx-target={@myself}
        aria-hidden="true"
      >
      </div>

      <aside
        id="admin-sidebar"
        class={
          [
            "bg-base-200 border-r border-base-300 transition-all duration-300 flex flex-col z-50",
            # Desktop - πάντα ορατό, scrollable
            "lg:relative lg:translate-x-0 lg:block lg:h-full",
            # Mobile - fixed overlay
            "fixed top-0 left-0 h-screen",
            @collapsed && "-translate-x-full lg:translate-x-0 lg:w-16",
            !@collapsed && "translate-x-0 w-64 lg:w-64"
          ]
        }
        role="navigation"
        aria-label="Admin navigation"
      >
        <!-- Mobile Header -->
        <div
          :if={@is_mobile?}
          class="lg:hidden flex items-center justify-between p-4 border-b border-base-300"
        >
          <h2 class="text-lg font-semibold">Admin Menu</h2>
          <button
            class="btn btn-ghost btn-sm"
            phx-click="toggle_sidebar"
            phx-target={@myself}
            aria-label="Close menu"
          >
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>

        <!-- Breadcrumbs -->
        <div :if={!@collapsed} class="px-4 py-3 border-b border-base-300">
          <nav class="text-sm" aria-label="Breadcrumb">
            <ol class="flex space-x-2">
              <li :for={{breadcrumb, index} <- Enum.with_index(@breadcrumbs)}>
                <span :if={index > 0} class="text-gray-400">/</span>
                <a href={breadcrumb.path} class="text-gray-600 hover:text-gray-900">
                  {breadcrumb.label}
                </a>
              </li>
            </ol>
          </nav>
        </div>

        <!-- Navigation Content -->
        <nav class="p-4 space-y-6 flex-1 overflow-y-auto">
          <div class="space-y-2">
            <h3 :if={!@collapsed} class="text-xs font-semibold text-gray-500 uppercase">
              Analytics
            </h3>
            <a
              :for={item <- @navigation_sections.analytics}
              href={item.href}
              class={[
                "flex items-center gap-3 px-3 py-2 rounded-lg transition-colors",
                @current_page == item.key && "bg-blue-100 text-blue-700",
                @current_page != item.key && "hover:bg-gray-100"
              ]}
              aria-current={@current_page == item.key && "page"}
            >
              <.icon name={item.icon} class="size-5 flex-shrink-0" />
              <span :if={!@collapsed}>{item.label}</span>
            </a>
          </div>

          <div class="space-y-2">
            <h3 :if={!@collapsed} class="text-xs font-semibold text-gray-500 uppercase">
              Operations
            </h3>
            <a
              :for={item <- @navigation_sections.operations}
              href={item.href}
              class={[
                "flex items-center gap-3 px-3 py-2 rounded-lg transition-colors",
                @current_page == item.key && "bg-blue-100 text-blue-700",
                @current_page != item.key && "hover:bg-gray-100"
              ]}
              aria-current={@current_page == item.key && "page"}
            >
              <.icon name={item.icon} class="size-5 flex-shrink-0" />
              <span :if={!@collapsed}>{item.label}</span>
            </a>
          </div>

          <div class="space-y-2">
            <h3 :if={!@collapsed} class="text-xs font-semibold text-gray-500 uppercase">
              Management
            </h3>
            <a
              :for={item <- @navigation_sections.management}
              href={item.href}
              class={[
                "flex items-center gap-3 px-3 py-2 rounded-lg transition-colors",
                @current_page == item.key && "bg-blue-100 text-blue-700",
                @current_page != item.key && "hover:bg-gray-100"
              ]}
              aria-current={@current_page == item.key && "page"}
            >
              <.icon name={item.icon} class="size-5 flex-shrink-0" />
              <span :if={!@collapsed}>{item.label}</span>
            </a>
          </div>
        </nav>

        <!-- Toggle Button -->
        <div class="p-4 border-t border-gray-200">
          <button
            class="flex items-center justify-center w-full p-2 hover:bg-gray-100 rounded-lg transition-colors"
            phx-click="toggle_sidebar"
            phx-target={@myself}
            aria-label={if @collapsed, do: "Expand sidebar", else: "Collapse sidebar"}
            aria-expanded={!@collapsed}
          >
            <.icon
              name={if @collapsed, do: "hero-chevron-right", else: "hero-chevron-left"}
              class="size-5"
            />
            <span :if={!@collapsed} class="ml-2 text-sm">Collapse</span>
          </button>
        </div>
      </aside>
    </div>
    """
  end

  @impl true
  def handle_event("toggle_sidebar", _params, socket) do
    # Στέλνουμε μήνυμα στο parent LiveView
    # Το LiveComponent τρέχει στο ίδιο process με το parent,
    # οπότε το self() είναι το parent process
    send(self(), {:toggle_sidebar})

    # Δεν αλλάζουμε το state εδώ - θα έρθει από το parent
    {:noreply, socket}
  end

  # Helper function to generate breadcrumbs based on current page
  defp generate_breadcrumbs(current_page) do
    base_breadcrumbs = [%{label: "Admin", path: "/admin"}]

    page_breadcrumb =
      case current_page do
        :dashboard -> %{label: "Dashboard", path: "/admin/dashboard"}
        :runs -> %{label: "Run History", path: "/admin/runs"}
        :chat -> %{label: "Chat Management", path: "/admin/chat"}
        :settings -> %{label: "Settings", path: "/admin/settings"}
        :profiles -> %{label: "Profile Management", path: "/admin/profiles"}
        :agents -> %{label: "Agent Management", path: "/admin/agents"}
        :workflows -> %{label: "Workflow Management", path: "/admin/workflows"}
        :testing -> %{label: "Testing Agents", path: "/admin/testing"}
        _ -> %{label: "Dashboard", path: "/admin/dashboard"}
      end

    base_breadcrumbs ++ [page_breadcrumb]
  end
end
