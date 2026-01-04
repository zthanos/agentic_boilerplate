defmodule AgentWebWeb.AdminUIComponents do
  @moduledoc """
  Reusable UI components for admin interface consistency.
  """
  use Phoenix.Component
  import AgentWebWeb.CoreComponents, only: [icon: 1]

  @doc """
  Renders an empty state with optional actions.
  """
  attr :title, :string, required: true
  attr :message, :string, required: true
  attr :icon, :string, default: "hero-inbox"
  attr :class, :string, default: ""
  slot :actions

  def empty_state(assigns) do
    ~H"""
    <div class={["flex flex-col items-center justify-center py-12 text-center", @class]}>
      <.icon name={@icon} class="size-12 text-base-content/30 mb-4" />
      <h3 class="text-lg font-semibold text-base-content/70 mb-2">{@title}</h3>
      
      <p class="text-sm text-base-content/50 max-w-md mb-4">{@message}</p>
      
      <%= if @actions != [] do %>
        <div class="flex gap-2">{render_slot(@actions)}</div>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders a header with title, subtitle, and actions.
  """
  attr :class, :string, default: ""
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <div class={["mb-6", @class]}>
      <div class="flex items-start justify-between">
        <div class="flex-1">
          <h1 class="text-3xl font-bold text-base-content">{render_slot(@inner_block)}</h1>
          
          <%= if @subtitle != [] do %>
            <p class="text-base-content/70 mt-2">{render_slot(@subtitle)}</p>
          <% end %>
        </div>
        
        <%= if @actions != [] do %>
          <div class="flex gap-2 ml-4">{render_slot(@actions)}</div>
        <% end %>
      </div>
    </div>
    """
  end

  @doc """
  Renders a stat card with optional trend indicator.
  """
  attr :title, :string, required: true
  attr :value, :any, required: true
  attr :icon, :string, required: true
  attr :trend, :string, default: nil
  attr :trend_positive, :boolean, default: true
  attr :class, :string, default: ""

  def stat_card(assigns) do
    ~H"""
    <div class={["card bg-base-200 shadow-sm", @class]}>
      <div class="card-body p-6">
        <div class="flex items-center justify-between">
          <div class="flex-1">
            <p class="text-sm text-base-content/70">{@title}</p>
            
            <p class="text-2xl font-bold mt-1">{@value}</p>
            
            <%= if @trend do %>
              <p class={[
                "text-sm font-medium mt-1",
                @trend_positive && "text-success",
                !@trend_positive && "text-error"
              ]}>
                {@trend}
              </p>
            <% end %>
          </div>
          
          <div class="p-3 bg-primary/10 rounded-lg">
            <.icon name={@icon} class="size-6 text-primary" />
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a loading skeleton for cards.
  """
  attr :rows, :integer, default: 3
  attr :class, :string, default: ""

  def loading_skeleton(assigns) do
    ~H"""
    <div class={["animate-pulse space-y-3", @class]}>
      <%= for _ <- 1..@rows do %>
        <div class="h-4 bg-base-300 rounded"></div>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders a progress bar with label.
  """
  attr :label, :string, default: nil
  attr :value, :integer, required: true
  attr :max, :integer, required: true
  attr :color, :string, default: "primary"
  attr :class, :string, default: ""

  def progress_bar(assigns) do
    percentage = min(100, round(assigns.value / assigns.max * 100))
    assigns = assign(assigns, :percentage, percentage)

    ~H"""
    <div class={@class}>
      <%= if @label do %>
        <div class="flex justify-between text-sm mb-1">
          <span>{@label}</span> <span>{@value}/{@max}</span>
        </div>
      <% end %>
      
      <div class="w-full bg-base-300 rounded-full h-2">
        <div
          class={["h-2 rounded-full transition-all duration-300", "bg-#{@color}"]}
          style={"width: #{@percentage}%"}
        >
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a badge with icon.
  """
  attr :icon, :string, default: nil
  attr :color, :string, default: "primary"
  attr :class, :string, default: ""
  slot :inner_block, required: true

  def badge_with_icon(assigns) do
    ~H"""
    <div class={["badge gap-2", "badge-#{@color}", @class]}>
      <%= if @icon do %>
        <.icon name={@icon} class="size-3" />
      <% end %>
       {render_slot(@inner_block)}
    </div>
    """
  end
end
