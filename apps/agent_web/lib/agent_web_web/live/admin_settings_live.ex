defmodule AgentWebWeb.AdminSettingsLive do
  @moduledoc """
  Admin settings management LiveView for system configuration.
  Provides interface for managing feature toggles, preferences, and environment variables.
  """
  use AgentWebWeb, :live_view
  alias AgentWebWeb.AdminLayouts

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to settings-related events
      Phoenix.PubSub.subscribe(AgentWeb.PubSub, "admin:settings")
    end

    {:ok,
     socket
     |> assign(:current_page, :settings)
     |> assign(:current_section, :management)
     |> assign(:sidebar_collapsed, false)
     |> assign(:page_title, "System Settings")
     |> assign(:active_tab, :general)
     |> assign(:unsaved_changes, false)
     |> load_settings_data()}
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
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, String.to_atom(tab))}
  end

  @impl true
  def handle_event("toggle_feature", %{"feature" => feature}, socket) do
    current_features = socket.assigns.feature_flags
    updated_features = Map.update!(current_features, String.to_atom(feature), &(!&1))

    {:noreply,
     socket
     |> assign(:feature_flags, updated_features)
     |> assign(:unsaved_changes, true)
     |> put_flash(:info, "Feature toggle updated")}
  end

  @impl true
  def handle_event("update_setting", %{"setting" => setting, "value" => value}, socket) do
    current_settings = socket.assigns.system_settings
    updated_settings = Map.put(current_settings, String.to_atom(setting), value)

    {:noreply,
     socket
     |> assign(:system_settings, updated_settings)
     |> assign(:unsaved_changes, true)}
  end

  @impl true
  def handle_event("save_settings", _params, socket) do
    # TODO: Implement actual settings persistence
    {:noreply,
     socket
     |> assign(:unsaved_changes, false)
     |> put_flash(:info, "Settings saved successfully")}
  end

  @impl true
  def handle_event("reset_settings", _params, socket) do
    {:noreply,
     socket
     |> load_settings_data()
     |> assign(:unsaved_changes, false)
     |> put_flash(:info, "Settings reset to defaults")}
  end

  @impl true
  def handle_event("export_config", _params, socket) do
    # TODO: Implement configuration export
    {:noreply, put_flash(socket, :info, "Configuration exported")}
  end

  @impl true
  def handle_event("import_config", _params, socket) do
    # TODO: Implement configuration import
    {:noreply, put_flash(socket, :info, "Configuration imported")}
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
      <!-- Header -->
      <div class="mb-8">
        <.header>
          System Settings
          <:subtitle>Configure system features, preferences, and environment variables</:subtitle>

          <:actions>
            <div class="flex gap-2">
              <button
                class="btn btn-outline btn-sm"
                phx-click="export_config"
              >
                <.icon name="hero-arrow-down-tray" class="size-4 mr-2" /> Export
              </button>
              <button
                class="btn btn-outline btn-sm"
                phx-click="import_config"
              >
                <.icon name="hero-arrow-up-tray" class="size-4 mr-2" /> Import
              </button>
              <button
                :if={@unsaved_changes}
                class="btn btn-warning btn-sm"
                phx-click="reset_settings"
              >
                <.icon name="hero-arrow-path" class="size-4 mr-2" /> Reset
              </button>
              <button
                :if={@unsaved_changes}
                class="btn btn-primary btn-sm"
                phx-click="save_settings"
              >
                <.icon name="hero-check" class="size-4 mr-2" /> Save Changes
              </button>
            </div>
          </:actions>
        </.header>
      </div>
      <!-- Settings Tabs -->
      <div class="tabs tabs-bordered mb-6">
        <button
          class={["tab", @active_tab == :general && "tab-active"]}
          phx-click="switch_tab"
          phx-value-tab="general"
        >
          <.icon name="hero-cog-6-tooth" class="size-4 mr-2" /> General
        </button>
        <button
          class={["tab", @active_tab == :features && "tab-active"]}
          phx-click="switch_tab"
          phx-value-tab="features"
        >
          <.icon name="hero-flag" class="size-4 mr-2" /> Features
        </button>
        <button
          class={["tab", @active_tab == :security && "tab-active"]}
          phx-click="switch_tab"
          phx-value-tab="security"
        >
          <.icon name="hero-shield-check" class="size-4 mr-2" /> Security
        </button>
        <button
          class={["tab", @active_tab == :performance && "tab-active"]}
          phx-click="switch_tab"
          phx-value-tab="performance"
        >
          <.icon name="hero-bolt" class="size-4 mr-2" /> Performance
        </button>
      </div>
      <!-- Tab Content -->
      <div :if={@active_tab == :general}><.general_settings settings={@system_settings} /></div>

      <div :if={@active_tab == :features}><.feature_flags flags={@feature_flags} /></div>

      <div :if={@active_tab == :security}><.security_settings settings={@security_settings} /></div>

      <div :if={@active_tab == :performance}>
        <.performance_settings settings={@performance_settings} />
      </div>
    </AdminLayouts.admin>
    """
  end

  # Load settings data
  defp load_settings_data(socket) do
    # TODO: Load actual settings from configuration
    system_settings = get_mock_system_settings()
    feature_flags = get_mock_feature_flags()
    security_settings = get_mock_security_settings()
    performance_settings = get_mock_performance_settings()

    socket
    |> assign(:system_settings, system_settings)
    |> assign(:feature_flags, feature_flags)
    |> assign(:security_settings, security_settings)
    |> assign(:performance_settings, performance_settings)
  end

  # Mock data functions
  defp get_mock_system_settings do
    %{
      app_name: "Agent Web",
      app_version: "1.0.0",
      environment: "development",
      timezone: "UTC",
      log_level: "info",
      max_concurrent_sessions: "10",
      session_timeout: "30",
      default_language: "en"
    }
  end

  defp get_mock_feature_flags do
    %{
      chat_enabled: true,
      agent_testing: true,
      run_history: true,
      real_time_updates: true,
      advanced_analytics: false,
      experimental_features: false,
      debug_mode: false,
      maintenance_mode: false
    }
  end

  defp get_mock_security_settings do
    %{
      require_authentication: true,
      session_encryption: true,
      api_rate_limiting: true,
      cors_enabled: false,
      csrf_protection: true,
      secure_headers: true,
      password_min_length: "8",
      max_login_attempts: "5"
    }
  end

  defp get_mock_performance_settings do
    %{
      cache_enabled: true,
      compression_enabled: true,
      static_file_caching: true,
      database_pool_size: "10",
      max_request_size: "10MB",
      response_timeout: "30s",
      gc_frequency: "5m",
      memory_limit: "1GB"
    }
  end

  # Settings components
  attr :settings, :map, required: true

  defp general_settings(assigns) do
    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
      <div class="card bg-base-200 shadow-sm">
        <div class="card-body">
          <h3 class="card-title text-lg">Application Settings</h3>

          <div class="space-y-4">
            <.setting_input
              label="Application Name"
              name="app_name"
              value={@settings.app_name}
              type="text"
            />
            <.setting_input
              label="Version"
              name="app_version"
              value={@settings.app_version}
              type="text"
              readonly={true}
            />
            <.setting_select
              label="Environment"
              name="environment"
              value={@settings.environment}
              options={[
                {"development", "Development"},
                {"staging", "Staging"},
                {"production", "Production"}
              ]}
            />
            <.setting_select
              label="Timezone"
              name="timezone"
              value={@settings.timezone}
              options={[
                {"UTC", "UTC"},
                {"America/New_York", "Eastern Time"},
                {"America/Los_Angeles", "Pacific Time"},
                {"Europe/London", "GMT"}
              ]}
            />
          </div>
        </div>
      </div>

      <div class="card bg-base-200 shadow-sm">
        <div class="card-body">
          <h3 class="card-title text-lg">System Configuration</h3>

          <div class="space-y-4">
            <.setting_select
              label="Log Level"
              name="log_level"
              value={@settings.log_level}
              options={[
                {"debug", "Debug"},
                {"info", "Info"},
                {"warn", "Warning"},
                {"error", "Error"}
              ]}
            />
            <.setting_input
              label="Max Concurrent Sessions"
              name="max_concurrent_sessions"
              value={@settings.max_concurrent_sessions}
              type="number"
            />
            <.setting_input
              label="Session Timeout (minutes)"
              name="session_timeout"
              value={@settings.session_timeout}
              type="number"
            />
            <.setting_select
              label="Default Language"
              name="default_language"
              value={@settings.default_language}
              options={[
                {"en", "English"},
                {"es", "Spanish"},
                {"fr", "French"},
                {"de", "German"}
              ]}
            />
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :flags, :map, required: true

  defp feature_flags(assigns) do
    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
      <div class="card bg-base-200 shadow-sm">
        <div class="card-body">
          <h3 class="card-title text-lg">Core Features</h3>

          <div class="space-y-4">
            <.feature_toggle
              label="Chat System"
              name="chat_enabled"
              enabled={@flags.chat_enabled}
              description="Enable the chat interface for user interactions"
            />
            <.feature_toggle
              label="Agent Testing"
              name="agent_testing"
              enabled={@flags.agent_testing}
              description="Enable agent testing and validation features"
            />
            <.feature_toggle
              label="Run History"
              name="run_history"
              enabled={@flags.run_history}
              description="Track and display execution history"
            />
            <.feature_toggle
              label="Real-time Updates"
              name="real_time_updates"
              enabled={@flags.real_time_updates}
              description="Enable live updates via WebSocket connections"
            />
          </div>
        </div>
      </div>

      <div class="card bg-base-200 shadow-sm">
        <div class="card-body">
          <h3 class="card-title text-lg">Advanced Features</h3>

          <div class="space-y-4">
            <.feature_toggle
              label="Advanced Analytics"
              name="advanced_analytics"
              enabled={@flags.advanced_analytics}
              description="Enable detailed analytics and reporting"
            />
            <.feature_toggle
              label="Experimental Features"
              name="experimental_features"
              enabled={@flags.experimental_features}
              description="Enable experimental and beta features"
            />
            <.feature_toggle
              label="Debug Mode"
              name="debug_mode"
              enabled={@flags.debug_mode}
              description="Enable debug logging and development tools"
            />
            <.feature_toggle
              label="Maintenance Mode"
              name="maintenance_mode"
              enabled={@flags.maintenance_mode}
              description="Put the system in maintenance mode"
            />
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :settings, :map, required: true

  defp security_settings(assigns) do
    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
      <div class="card bg-base-200 shadow-sm">
        <div class="card-body">
          <h3 class="card-title text-lg">Authentication & Authorization</h3>

          <div class="space-y-4">
            <.feature_toggle
              label="Require Authentication"
              name="require_authentication"
              enabled={@settings.require_authentication}
              description="Require users to authenticate before accessing the system"
            />
            <.feature_toggle
              label="Session Encryption"
              name="session_encryption"
              enabled={@settings.session_encryption}
              description="Encrypt session data for enhanced security"
            />
            <.setting_input
              label="Password Min Length"
              name="password_min_length"
              value={@settings.password_min_length}
              type="number"
            />
            <.setting_input
              label="Max Login Attempts"
              name="max_login_attempts"
              value={@settings.max_login_attempts}
              type="number"
            />
          </div>
        </div>
      </div>

      <div class="card bg-base-200 shadow-sm">
        <div class="card-body">
          <h3 class="card-title text-lg">API & Network Security</h3>

          <div class="space-y-4">
            <.feature_toggle
              label="API Rate Limiting"
              name="api_rate_limiting"
              enabled={@settings.api_rate_limiting}
              description="Limit API requests to prevent abuse"
            />
            <.feature_toggle
              label="CORS Enabled"
              name="cors_enabled"
              enabled={@settings.cors_enabled}
              description="Enable Cross-Origin Resource Sharing"
            />
            <.feature_toggle
              label="CSRF Protection"
              name="csrf_protection"
              enabled={@settings.csrf_protection}
              description="Protect against Cross-Site Request Forgery"
            />
            <.feature_toggle
              label="Secure Headers"
              name="secure_headers"
              enabled={@settings.secure_headers}
              description="Add security headers to HTTP responses"
            />
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :settings, :map, required: true

  defp performance_settings(assigns) do
    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
      <div class="card bg-base-200 shadow-sm">
        <div class="card-body">
          <h3 class="card-title text-lg">Caching & Optimization</h3>

          <div class="space-y-4">
            <.feature_toggle
              label="Cache Enabled"
              name="cache_enabled"
              enabled={@settings.cache_enabled}
              description="Enable application-level caching"
            />
            <.feature_toggle
              label="Compression Enabled"
              name="compression_enabled"
              enabled={@settings.compression_enabled}
              description="Enable response compression"
            />
            <.feature_toggle
              label="Static File Caching"
              name="static_file_caching"
              enabled={@settings.static_file_caching}
              description="Cache static assets for better performance"
            />
          </div>
        </div>
      </div>

      <div class="card bg-base-200 shadow-sm">
        <div class="card-body">
          <h3 class="card-title text-lg">Resource Limits</h3>

          <div class="space-y-4">
            <.setting_input
              label="Database Pool Size"
              name="database_pool_size"
              value={@settings.database_pool_size}
              type="number"
            />
            <.setting_input
              label="Max Request Size"
              name="max_request_size"
              value={@settings.max_request_size}
              type="text"
            />
            <.setting_input
              label="Response Timeout"
              name="response_timeout"
              value={@settings.response_timeout}
              type="text"
            />
            <.setting_input
              label="Memory Limit"
              name="memory_limit"
              value={@settings.memory_limit}
              type="text"
            />
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Helper components
  attr :label, :string, required: true
  attr :name, :string, required: true
  attr :value, :string, required: true
  attr :type, :string, default: "text"
  attr :readonly, :boolean, default: false

  defp setting_input(assigns) do
    ~H"""
    <div class="form-control">
      <label class="label"><span class="label-text font-medium">{@label}</span></label>
      <input
        type={@type}
        name={@name}
        value={@value}
        readonly={@readonly}
        class={[
          "input input-bordered input-sm",
          @readonly && "input-disabled"
        ]}
        phx-change="update_setting"
        phx-value-setting={@name}
      />
    </div>
    """
  end

  attr :label, :string, required: true
  attr :name, :string, required: true
  attr :value, :string, required: true
  attr :options, :list, required: true

  defp setting_select(assigns) do
    ~H"""
    <div class="form-control">
      <label class="label"><span class="label-text font-medium">{@label}</span></label>
      <select
        name={@name}
        class="select select-bordered select-sm"
        phx-change="update_setting"
        phx-value-setting={@name}
      >
        <option
          :for={{value, label} <- @options}
          value={value}
          selected={value == @value}
        >
          {label}
        </option>
      </select>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :name, :string, required: true
  attr :enabled, :boolean, required: true
  attr :description, :string, required: true

  defp feature_toggle(assigns) do
    ~H"""
    <div class="form-control">
      <label class="label cursor-pointer justify-start gap-4">
        <input
          type="checkbox"
          class="toggle toggle-primary"
          checked={@enabled}
          phx-click="toggle_feature"
          phx-value-feature={@name}
        />
        <div>
          <span class="label-text font-medium">{@label}</span>
          <p class="text-xs text-base-content/70 mt-1">{@description}</p>
        </div>
      </label>
    </div>
    """
  end
end
