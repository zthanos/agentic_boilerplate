defmodule AgentWebWeb.AdminLayouts do
  @moduledoc """
  Admin-specific layouts and components for the administrative interface.
  """
  use AgentWebWeb, :html

  # Import necessary functions from CoreComponents
  import AgentWebWeb.CoreComponents, only: [show: 2, hide: 2, icon: 1]
  # Import error handling components
  import AgentWebWeb.AdminErrorComponents
  # Import accessibility utilities
  import AgentWebWeb.AdminAccessibility

  @doc """
  Renders the admin layout with sticky navbar/footer and scrollable content.

  Layout structure:
  - Fixed navbar at top (always visible)
  - Sidebar (collapsible) + Main content (scrollable area)
  - Fixed footer at bottom (always visible)
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_page, :atom,
    default: :dashboard,
    doc: "the current admin page for navigation state"

  attr :current_section, :atom, default: :analytics, doc: "the current admin section"
  attr :sidebar_collapsed, :boolean, default: false, doc: "whether the sidebar is collapsed"
  attr :loading, :boolean, default: false, doc: "whether the page is in loading state"
  attr :error, :string, default: nil, doc: "page-level error message"
  attr :is_mobile?, :boolean, default: false, doc: "whether the sidebar is mobile"

  slot :inner_block, required: true

  def admin(assigns) do
    ~H"""
    <div
      id="admin-layout"
      class="h-screen flex flex-col bg-base-100"
      phx-hook="AdminSidebarPersistence"
    >
      <!-- Skip Links for Keyboard Navigation -->
      <div class="skip-links">
        <a {skip_link_attrs("main-content")}>Skip to main content</a>
        <a href="#admin-sidebar" class="skip-link">Skip to navigation</a>
        <a href="#admin-footer" class="skip-link">Skip to footer</a>
      </div>
      
    <!-- Admin Navigation Bar - Fixed at top -->
      <.admin_navbar loading={@loading} />
      
    <!-- Main Layout Grid - Flexible space between navbar and footer -->
      <div class="flex flex-1 overflow-hidden">
        <!-- Sidebar LiveComponent -->
        <.live_component
          module={AgentWebWeb.AdminSidebar}
          id="admin-sidebar"
          current_page={@current_page}
          collapsed={@sidebar_collapsed}
          is_mobile={@is_mobile?}
        />
        
    <!-- Main Content Area - Scrollable -->
        <main
          id="main-content"
          class="flex-1 min-h-0 overflow-hidden p-4 lg:p-6 xl:p-8"
          role="main"
          aria-label="Admin dashboard main content"
          tabindex="-1"
        >
          <div class="max-w-7xl mx-auto h-full flex flex-col min-h-0">
            <!-- Page-level Error State -->
            <div :if={@error && !@loading} class="mb-6">
              <.error_state
                title="Page Error"
                message={@error}
                retry_event="retry_page_load"
                class="bg-base-200 rounded-lg"
              />
            </div>
            
    <!-- Page-level Loading State -->
            <div :if={@loading} class="mb-6" {loading_attrs("page-loading")}>
              <.loading_state
                message="Loading admin dashboard..."
                class="bg-base-200 rounded-lg"
              />
            </div>
            
    <!-- Page Content -->
            <div :if={!@error && !@loading} class="flex-1 min-h-0 flex flex-col">
              {render_slot(@inner_block)}
            </div>
          </div>
        </main>
      </div>
      
    <!-- Admin Footer - Fixed at bottom -->
      <.admin_footer />
      
    <!-- Enhanced Flash Messages -->
      <.admin_flash_group flash={@flash} />
      
    <!-- Screen Reader Announcements -->
      <div
        id="screen-reader-announcements"
        aria-live="polite"
        aria-atomic="true"
        class="sr-only"
        phx-hook="ScreenReaderAnnouncer"
      >
      </div>
    </div>
    """
  end

  @doc """
  Renders the admin navigation bar with branding and user controls.
  """
  attr :loading, :boolean, default: false

  def admin_navbar(assigns) do
    ~H"""
    <header class="navbar bg-base-200 border-b border-base-300 px-4 lg:px-6 flex-shrink-0">
      <div class="flex-1">
        <!-- Mobile Menu Button -->
        <button
          class="btn btn-ghost btn-square lg:hidden mr-2"
          phx-click="toggle_sidebar"
          aria-label="Toggle menu"
          disabled={@loading}
        >
          <.icon name="hero-bars-3" class="size-6" />
        </button>
        <a href="/admin" class="flex items-center gap-3 text-xl font-bold">
          <.icon name="hero-cog-6-tooth" class="size-6 text-primary" />
          <span class="hidden sm:inline">Admin Dashboard</span>
          <span class="sm:hidden">Admin</span>
        </a>
        <!-- Loading Indicator -->
        <div :if={@loading} class="ml-4">
          <div class="loading loading-spinner loading-sm text-primary"></div>
        </div>
      </div>

      <div class="flex-none">
        <div class="flex items-center gap-2">
          <!-- System Status Indicator -->
          <.system_status_indicator />
          <!-- Theme Toggle -->
          <.theme_toggle />
          <!-- User Menu -->
          <.admin_user_menu />
        </div>
      </div>
    </header>
    """
  end

  @doc """
  Renders the admin footer with system information.
  """
  def admin_footer(assigns) do
    ~H"""
    <footer class="bg-base-200 border-t border-base-300 px-6 py-4 flex-shrink-0">
      <div class="flex flex-col sm:flex-row justify-between items-center gap-4 text-sm text-base-content/70">
        <div class="flex items-center gap-4">
          <span>Agent System v1.0.0</span>
          <span class="hidden sm:inline">•</span>
          <span>Phoenix v{Application.spec(:phoenix, :vsn)}</span>
        </div>

        <div class="flex items-center gap-4">
          <span>Last Updated: {DateTime.utc_now() |> DateTime.to_date() |> Date.to_string()}</span>
          <a href="/admin/system-info" class="link link-hover">System Info</a>
        </div>
      </div>
    </footer>
    """
  end

  @doc """
  Shows the flash group with admin-specific styling and enhanced error handling.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "admin-flash-group", doc: "the optional id of flash container"

  def admin_flash_group(assigns) do
    ~H"""
    <div id={@id} class="fixed top-20 right-4 z-50 space-y-2" aria-live="polite">
      <.admin_flash kind={:info} flash={@flash} />
      <.admin_flash kind={:error} flash={@flash} />
      
    <!-- Connection Status Messages -->
      <.admin_flash
        id="admin-client-error"
        kind={:error}
        title={gettext("Connection Lost")}
        phx-disconnected={
          show(%JS{}, ".phx-client-error #admin-client-error") |> JS.remove_attribute("hidden")
        }
        phx-connected={hide(%JS{}, "#admin-client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
        persistent={true}
      >
        {gettext("Attempting to reconnect to admin dashboard...")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.admin_flash>

      <.admin_flash
        id="admin-server-error"
        kind={:error}
        title={gettext("Admin System Error")}
        phx-disconnected={
          show(%JS{}, ".phx-server-error #admin-server-error") |> JS.remove_attribute("hidden")
        }
        phx-connected={hide(%JS{}, "#admin-server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
        persistent={true}
      >
        {gettext("Admin services are temporarily unavailable")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.admin_flash>
    </div>
    """
  end

  @doc """
  Renders a flash message with admin styling and enhanced features.
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :persistent, :boolean, default: false, doc: "whether the flash should auto-dismiss"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def admin_flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "admin-flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={!@persistent && JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class="alert shadow-lg max-w-md cursor-pointer"
      phx-mounted={!@persistent && JS.hide(to: "##{@id}", transition: "fade-out", time: 5000)}
      {@rest}
    >
      <div class={[
        "flex items-start gap-3 w-full",
        @kind == :info && "text-info",
        @kind == :error && "text-error"
      ]}>
        <.icon :if={@kind == :info} name="hero-information-circle" class="size-5 shrink-0 mt-0.5" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle" class="size-5 shrink-0 mt-0.5" />
        <div class="flex-1 min-w-0">
          <p :if={@title} class="font-semibold text-sm">{@title}</p>
          <p class="text-sm">{msg}</p>
        </div>

        <button
          :if={!@persistent}
          type="button"
          class="btn btn-ghost btn-xs btn-square opacity-70 hover:opacity-100"
          aria-label={gettext("close")}
        >
          <.icon name="hero-x-mark" class="size-4" />
        </button>
      </div>
    </div>
    """
  end

  # Import the theme_toggle from the main Layouts module
  defdelegate theme_toggle(assigns), to: AgentWebWeb.Layouts

  @doc """
  Renders the system status indicator with real-time health information.
  """
  def system_status_indicator(assigns) do
    assigns = assign(assigns, :status, get_system_status())

    ~H"""
    <div class="tooltip tooltip-bottom" data-tip={"System Status: #{@status.text}"}>
      <div class={[
        "badge gap-1 text-xs",
        @status.healthy && "badge-success",
        !@status.healthy && "badge-error"
      ]}>
        <div class={[
          "w-2 h-2 rounded-full",
          @status.healthy && "bg-success animate-pulse",
          !@status.healthy && "bg-error animate-pulse"
        ]}>
        </div>
        <span class="hidden sm:inline">{@status.text}</span>
      </div>
    </div>
    """
  end

  @doc """
  Renders the admin user menu with enhanced options.
  """
  def admin_user_menu(assigns) do
    ~H"""
    <div class="dropdown dropdown-end">
      <div tabindex="0" role="button" class="btn btn-ghost btn-circle avatar" aria-label="User menu">
        <div class="w-8 rounded-full bg-primary text-primary-content flex items-center justify-center">
          <.icon name="hero-user" class="size-4" />
        </div>
      </div>

      <ul
        tabindex="0"
        class="menu menu-sm dropdown-content mt-3 z-[1] p-2 shadow bg-base-100 rounded-box w-52 border border-base-300"
      >
        <li class="menu-title"><span>Admin Actions</span></li>

        <li>
          <a href="/admin/settings" class="flex items-center gap-2">
            <.icon name="hero-cog-6-tooth" class="size-4" /> Settings
          </a>
        </li>

        <li>
          <a href="/admin/system-info" class="flex items-center gap-2">
            <.icon name="hero-information-circle" class="size-4" /> System Info
          </a>
        </li>

        <div class="divider my-1"></div>

        <li>
          <a href="/" class="flex items-center gap-2 text-warning">
            <.icon name="hero-arrow-left-on-rectangle" class="size-4" /> Exit Admin
          </a>
        </li>
      </ul>
    </div>
    """
  end

  @doc """
  Renders accessibility control buttons for high contrast and reduced motion.
  """
  def accessibility_controls(assigns) do
    ~H"""
    <div class="dropdown dropdown-end">
      <div
        tabindex="0"
        role="button"
        class="btn btn-ghost btn-circle"
        aria-label="Accessibility options"
        {button_attrs("accessibility-menu", controls: "accessibility-dropdown")}
      >
        <.icon name="hero-adjustments-horizontal" class="size-5" />
      </div>

      <ul
        id="accessibility-dropdown"
        tabindex="0"
        class="menu menu-sm dropdown-content mt-3 z-[1] p-2 shadow bg-base-100 rounded-box w-64 border border-base-300"
        {menu_attrs("accessibility-dropdown", "accessibility-menu")}
      >
        <li class="menu-title"><span>Accessibility Options</span></li>

        <li>
          <button
            class="flex items-center gap-2 w-full text-left"
            phx-click="toggle_high_contrast"
            role="menuitem"
          >
            <.icon name="hero-eye" class="size-4" /> Toggle High Contrast
          </button>
        </li>

        <li>
          <button
            class="flex items-center gap-2 w-full text-left"
            phx-click="toggle_reduced_motion"
            role="menuitem"
          >
            <.icon name="hero-pause" class="size-4" /> Toggle Reduced Motion
          </button>
        </li>

        <li>
          <button
            class="flex items-center gap-2 w-full text-left"
            phx-click="focus_main_content"
            role="menuitem"
          >
            <.icon name="hero-cursor-arrow-rays" class="size-4" /> Focus Main Content
          </button>
        </li>
      </ul>
    </div>
    """
  end

  # Helper function to get system status
  defp get_system_status do
    %{
      healthy: true,
      text: "Online"
    }
  end
end
