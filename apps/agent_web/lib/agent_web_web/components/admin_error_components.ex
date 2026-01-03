defmodule AgentWebWeb.AdminErrorComponents do
  @moduledoc """
  Error handling and user feedback components for the admin dashboard.

  Provides comprehensive error handling with:
  - Loading states and spinners
  - Error messages and alerts
  - Graceful degradation for failed services
  - User feedback and notifications
  - Retry mechanisms and fallback content
  """
  use AgentWebWeb, :html

  @doc """
  Renders a loading state with spinner and optional message.

  ## Examples

      <.loading_state message="Loading dashboard data..." />
      <.loading_state size="lg" />
  """
  attr :message, :string, default: "Loading..."
  attr :size, :string, default: "md", values: ["sm", "md", "lg"]
  attr :class, :string, default: ""
  attr :rest, :global

  def loading_state(assigns) do
    size_classes = %{
      "sm" => "size-4",
      "md" => "size-6",
      "lg" => "size-8"
    }

    assigns = assign(assigns, :size_class, size_classes[assigns.size])

    ~H"""
    <div class={["flex flex-col items-center justify-center p-8 text-center", @class]} {@rest}>
      <div class="loading loading-spinner loading-lg text-primary mb-4"></div>
      
      <p class="text-base-content/70 animate-pulse">{@message}</p>
    </div>
    """
  end

  @doc """
  Renders an error state with icon, message, and optional retry action.

  ## Examples

      <.error_state
        title="Failed to load data"
        message="Unable to connect to the database"
        retry_event="retry_load"
      />
  """
  attr :title, :string, required: true
  attr :message, :string, required: true
  attr :retry_event, :string, default: nil
  attr :retry_target, :any, default: nil
  attr :icon, :string, default: "hero-exclamation-triangle"
  attr :class, :string, default: ""
  attr :rest, :global

  def error_state(assigns) do
    ~H"""
    <div class={["flex flex-col items-center justify-center p-8 text-center", @class]} {@rest}>
      <div class="p-4 bg-error/10 rounded-full mb-4">
        <.icon name={@icon} class="size-8 text-error" />
      </div>
      
      <h3 class="text-lg font-semibold text-base-content mb-2">{@title}</h3>
      
      <p class="text-base-content/70 mb-6 max-w-md">{@message}</p>
      
      <button
        :if={@retry_event}
        class="btn btn-outline btn-sm"
        phx-click={@retry_event}
        phx-target={@retry_target}
      >
        <.icon name="hero-arrow-path" class="size-4 mr-2" /> Try Again
      </button>
    </div>
    """
  end

  @doc """
  Renders an empty state with icon, message, and optional action.

  ## Examples

      <.empty_state
        title="No data available"
        message="There are no items to display"
        action_text="Create New"
        action_event="create_new"
      />
  """
  attr :title, :string, required: true
  attr :message, :string, required: true
  attr :action_text, :string, default: nil
  attr :action_event, :string, default: nil
  attr :action_target, :any, default: nil
  attr :icon, :string, default: "hero-inbox"
  attr :class, :string, default: ""
  attr :rest, :global

  def empty_state(assigns) do
    ~H"""
    <div class={["flex flex-col items-center justify-center p-12 text-center", @class]} {@rest}>
      <div class="p-4 bg-base-300/50 rounded-full mb-4">
        <.icon name={@icon} class="size-12 text-base-content/30" />
      </div>
      
      <h3 class="text-lg font-semibold text-base-content mb-2">{@title}</h3>
      
      <p class="text-base-content/70 mb-6 max-w-md">{@message}</p>
      
      <button
        :if={@action_text && @action_event}
        class="btn btn-primary btn-sm"
        phx-click={@action_event}
        phx-target={@action_target}
      >
        <.icon name="hero-plus" class="size-4 mr-2" /> {@action_text}
      </button>
    </div>
    """
  end

  @doc """
  Renders a service status indicator with degradation handling.

  ## Examples

      <.service_status
        name="Database"
        status={:healthy}
        details="Connection: 5ms"
      />

      <.service_status
        name="LLM Service"
        status={:degraded}
        details="Limited functionality available"
        fallback_message="Using cached responses"
      />
  """
  attr :name, :string, required: true
  attr :status, :atom, required: true, values: [:healthy, :warning, :error, :degraded, :offline]
  attr :details, :string, default: ""
  attr :fallback_message, :string, default: nil
  attr :class, :string, default: ""
  attr :rest, :global

  def service_status(assigns) do
    {status_class, status_icon, status_text} =
      case assigns.status do
        :healthy -> {"text-success", "hero-check-circle", "Healthy"}
        :warning -> {"text-warning", "hero-exclamation-triangle", "Warning"}
        :error -> {"text-error", "hero-x-circle", "Error"}
        :degraded -> {"text-warning", "hero-signal-slash", "Degraded"}
        :offline -> {"text-error", "hero-wifi-slash", "Offline"}
      end

    assigns = assign(assigns, :status_class, status_class)
    assigns = assign(assigns, :status_icon, status_icon)
    assigns = assign(assigns, :status_text, status_text)

    ~H"""
    <div class={["flex items-start gap-3 p-3 rounded-lg bg-base-200", @class]} {@rest}>
      <.icon name={@status_icon} class={"size-5 mt-0.5 " <> @status_class} />
      <div class="flex-1 min-w-0">
        <div class="flex items-center justify-between">
          <h4 class="font-medium text-base-content">{@name}</h4>
           <span class={"text-sm font-medium " <> @status_class}>{@status_text}</span>
        </div>
        
        <p :if={@details != ""} class="text-sm text-base-content/70 mt-1">{@details}</p>
        
        <div
          :if={@fallback_message && @status in [:degraded, :error]}
          class="mt-2 p-2 bg-warning/10 rounded text-sm"
        >
          <.icon name="hero-information-circle" class="size-4 text-warning inline mr-1" /> {@fallback_message}
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a data table with loading, error, and empty states.

  ## Examples

      <.data_table
        id="users-table"
        loading={@loading}
        error={@error}
        data={@users}
        columns={[
          %{key: :name, label: "Name"},
          %{key: :email, label: "Email"}
        ]}
      />
  """
  attr :id, :string, required: true
  attr :loading, :boolean, default: false
  attr :error, :string, default: nil
  attr :data, :list, default: []
  attr :columns, :list, required: true
  attr :empty_message, :string, default: "No data available"
  attr :retry_event, :string, default: nil
  attr :retry_target, :any, default: nil
  attr :class, :string, default: ""
  attr :rest, :global

  def data_table(assigns) do
    ~H"""
    <div class={["overflow-x-auto", @class]} {@rest}>
      <table class="table table-zebra w-full">
        <thead>
          <tr>
            <th :for={column <- @columns} class="font-semibold">{column.label}</th>
          </tr>
        </thead>
        
        <tbody>
          <!-- Loading State -->
          <tr :if={@loading}>
            <td :for={_column <- @columns} class="text-center py-8">
              <div class="loading loading-spinner loading-sm"></div>
            </td>
          </tr>
          <!-- Error State -->
          <tr :if={@error && !@loading}>
            <td colspan={length(@columns)} class="text-center py-8">
              <.error_state
                title="Failed to load data"
                message={@error}
                retry_event={@retry_event}
                retry_target={@retry_target}
                class="py-4"
              />
            </td>
          </tr>
          <!-- Empty State -->
          <tr :if={!@loading && !@error && Enum.empty?(@data)}>
            <td colspan={length(@columns)} class="text-center py-8">
              <.empty_state
                title="No data available"
                message={@empty_message}
                class="py-4"
              />
            </td>
          </tr>
          <!-- Data Rows -->
          <tr :for={row <- @data} :if={!@loading && !@error && !Enum.empty?(@data)}>
            <td :for={column <- @columns}>{get_in(row, [Access.key(column.key)])}</td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @doc """
  Renders a form with loading and error states.

  ## Examples

      <.form_wrapper
        loading={@saving}
        error={@form_error}
        success_message={@success_message}
      >
        <.input field={@form[:name]} label="Name" />
        <.input field={@form[:email]} label="Email" />
      </.form_wrapper>
  """
  attr :loading, :boolean, default: false
  attr :error, :string, default: nil
  attr :success_message, :string, default: nil
  attr :class, :string, default: ""
  attr :rest, :global
  slot :inner_block, required: true

  def form_wrapper(assigns) do
    ~H"""
    <div class={["relative", @class]} {@rest}>
      <!-- Success Message -->
      <div :if={@success_message} class="alert alert-success mb-4">
        <.icon name="hero-check-circle" class="size-5" /> <span>{@success_message}</span>
      </div>
      <!-- Error Message -->
      <div :if={@error} class="alert alert-error mb-4">
        <.icon name="hero-exclamation-circle" class="size-5" /> <span>{@error}</span>
      </div>
      <!-- Form Content -->
      <div class={@loading && "opacity-50 pointer-events-none"}>{render_slot(@inner_block)}</div>
      <!-- Loading Overlay -->
      <div
        :if={@loading}
        class="absolute inset-0 flex items-center justify-center bg-base-100/50 rounded-lg"
      >
        <div class="loading loading-spinner loading-lg text-primary"></div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a card with loading, error, and content states.

  ## Examples

      <.card_wrapper
        title="System Metrics"
        loading={@loading_metrics}
        error={@metrics_error}
        retry_event="reload_metrics"
      >
        <p>Metrics content here</p>
      </.card_wrapper>
  """
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :loading, :boolean, default: false
  attr :error, :string, default: nil
  attr :retry_event, :string, default: nil
  attr :retry_target, :any, default: nil
  attr :actions, :list, default: []
  attr :class, :string, default: ""
  attr :rest, :global
  slot :inner_block, required: true

  def card_wrapper(assigns) do
    ~H"""
    <div class={["card bg-base-200 shadow-sm", @class]} {@rest}>
      <div class="card-body">
        <!-- Card Header -->
        <div class="flex items-center justify-between mb-4">
          <div>
            <h3 class="card-title text-lg">{@title}</h3>
            
            <p :if={@subtitle} class="text-sm text-base-content/70 mt-1">{@subtitle}</p>
          </div>
          
          <div :if={!Enum.empty?(@actions)} class="flex gap-2">
            <button
              :for={action <- @actions}
              class={action[:class] || "btn btn-sm btn-ghost"}
              phx-click={action[:event]}
              phx-target={action[:target]}
            >
              <.icon :if={action[:icon]} name={action[:icon]} class="size-4 mr-1" /> {action[:text]}
            </button>
          </div>
        </div>
        <!-- Loading State -->
        <div :if={@loading}><.loading_state message="Loading..." /></div>
        <!-- Error State -->
        <div :if={@error && !@loading}>
          <.error_state
            title="Failed to load content"
            message={@error}
            retry_event={@retry_event}
            retry_target={@retry_target}
          />
        </div>
        <!-- Content -->
        <div :if={!@loading && !@error}>{render_slot(@inner_block)}</div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a notification toast with auto-dismiss functionality.

  ## Examples

      <.notification
        id="success-toast"
        type="success"
        title="Settings saved"
        message="Your changes have been applied successfully"
        auto_dismiss={5000}
      />
  """
  attr :id, :string, required: true
  attr :type, :atom, required: true, values: [:info, :success, :warning, :error]
  attr :title, :string, required: true
  attr :message, :string, required: true
  attr :auto_dismiss, :integer, default: nil
  attr :dismissible, :boolean, default: true
  attr :class, :string, default: ""
  attr :rest, :global

  def notification(assigns) do
    {alert_class, icon_name} =
      case assigns.type do
        :info -> {"alert-info", "hero-information-circle"}
        :success -> {"alert-success", "hero-check-circle"}
        :warning -> {"alert-warning", "hero-exclamation-triangle"}
        :error -> {"alert-error", "hero-exclamation-circle"}
      end

    assigns = assign(assigns, :alert_class, alert_class)
    assigns = assign(assigns, :icon_name, icon_name)

    ~H"""
    <div
      id={@id}
      class={["alert shadow-lg max-w-md", @alert_class, @class]}
      phx-mounted={
        @auto_dismiss && JS.hide(to: "##{@id}", transition: "fade-out", time: @auto_dismiss)
      }
      {@rest}
    >
      <.icon name={@icon_name} class="size-5 shrink-0" />
      <div class="flex-1">
        <h4 class="font-semibold">{@title}</h4>
        
        <p class="text-sm opacity-90">{@message}</p>
      </div>
      
      <button
        :if={@dismissible}
        type="button"
        class="btn btn-ghost btn-sm btn-square"
        phx-click={JS.hide(to: "##{@id}", transition: "fade-out")}
        aria-label="Dismiss notification"
      >
        <.icon name="hero-x-mark" class="size-4" />
      </button>
    </div>
    """
  end
end
