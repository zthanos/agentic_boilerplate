defmodule AgentWebWeb.ErrorDisplayComponent do
  @moduledoc """
  Reusable error display component with consistent styling and recovery options.

  Provides standardized error display across the agent testing interface with:
  - Consistent visual styling using existing design system
  - Contextual recovery actions based on error type
  - User-friendly error messages with troubleshooting guidance
  - Accessibility features for screen readers
  """

  use AgentWebWeb, :live_component

  @doc """
  Renders an error display with appropriate recovery options.

  ## Attributes
  - `error` - The error message or error struct to display
  - `error_type` - Type of error (:connection, :timeout, :validation, :agent, :workflow, :general)
  - `context` - Context where error occurred (:agent_selection, :workflow, :chat, :seeding)
  - `recovery_actions` - List of recovery action maps with :label, :event, and optional :params
  - `dismissible` - Whether the error can be dismissed (default: true)
  - `class` - Additional CSS classes
  """

  def render(assigns) do
    ~H"""
    <div class={["alert alert-error", @class]} role="alert" aria-live="polite">
      <div class="flex items-start gap-3">
        <!-- Error Icon -->
        <div class="shrink-0">{error_icon(@error_type)}</div>
        <!-- Error Content -->
        <div class="flex-1 min-w-0">
          <h3 class="font-bold text-sm">{error_title(@error_type, @context)}</h3>

          <div class="text-sm mt-1 break-words">{format_error_message(@error)}</div>
          <!-- Troubleshooting Guidance -->
          <%= if troubleshooting_guidance(@error_type, @context) do %>
            <details class="mt-2">
              <summary class="text-xs cursor-pointer hover:underline">Troubleshooting Tips</summary>

              <div class="text-xs mt-1 pl-2 border-l-2 border-error/30">
                {troubleshooting_guidance(@error_type, @context)}
              </div>
            </details>
          <% end %>
        </div>
        <!-- Dismiss Button -->
        <%= if @dismissible do %>
          <button
            class="btn btn-ghost btn-xs shrink-0"
            phx-click="clear_error"
            phx-target={@myself}
            aria-label="Dismiss error"
          >
            ✕
          </button>
        <% end %>
      </div>
      <!-- Recovery Actions -->
      <%= if @recovery_actions && length(@recovery_actions) > 0 do %>
        <div class="flex flex-wrap gap-2 mt-3 pt-3 border-t border-error/20">
          <%= for action <- @recovery_actions do %>
            <button
              class="btn btn-sm btn-outline btn-error"
              phx-click={action.event}
              phx-value-params={Jason.encode!(action[:params] || %{})}
              phx-target={@myself}
            >
              {action.label}
            </button>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  # Event handlers for recovery actions
  def handle_event("clear_error", _params, socket) do
    send(self(), {:clear_error})
    {:noreply, socket}
  end

  def handle_event(event, %{"params" => params_json}, socket) do
    params = Jason.decode!(params_json)
    send(self(), {:recovery_action, event, params})
    {:noreply, socket}
  end

  def handle_event(event, params, socket) do
    send(self(), {:recovery_action, event, params})
    {:noreply, socket}
  end

  # Private helper functions

  defp error_icon(:connection) do
    assigns = %{}

    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      class="h-5 w-5 stroke-current"
      fill="none"
      viewBox="0 0 24 24"
    >
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        stroke-width="2"
        d="M8.111 16.404a5.5 5.5 0 017.778 0M12 20h.01m-7.08-7.071c3.904-3.905 10.236-3.905 14.141 0M1.394 9.393c5.857-5.857 15.355-5.857 21.213 0"
      />
    </svg>
    """
  end

  defp error_icon(:timeout) do
    assigns = %{}

    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      class="h-5 w-5 stroke-current"
      fill="none"
      viewBox="0 0 24 24"
    >
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        stroke-width="2"
        d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
      />
    </svg>
    """
  end

  defp error_icon(:validation) do
    assigns = %{}

    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      class="h-5 w-5 stroke-current"
      fill="none"
      viewBox="0 0 24 24"
    >
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        stroke-width="2"
        d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L3.732 16.5c-.77.833.192 2.5 1.732 2.5z"
      />
    </svg>
    """
  end

  defp error_icon(_) do
    assigns = %{}

    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      class="h-5 w-5 stroke-current"
      fill="none"
      viewBox="0 0 24 24"
    >
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        stroke-width="2"
        d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z"
      />
    </svg>
    """
  end

  defp error_title(:connection, :chat), do: "Connection Error"
  defp error_title(:connection, _), do: "Connection Failed"
  defp error_title(:timeout, :chat), do: "Response Timeout"
  defp error_title(:timeout, _), do: "Operation Timeout"
  defp error_title(:validation, :agent), do: "Agent Configuration Error"
  defp error_title(:validation, _), do: "Validation Error"
  defp error_title(:agent, _), do: "Agent Error"
  defp error_title(:workflow, _), do: "Workflow Error"
  defp error_title(:seeding, _), do: "Agent Seeding Error"
  defp error_title(_, _), do: "Error"

  defp format_error_message(error) when is_binary(error), do: error
  defp format_error_message(error) when is_atom(error), do: Atom.to_string(error)
  defp format_error_message(error), do: inspect(error)

  defp troubleshooting_guidance(:connection, :chat) do
    """
    • Check if LM Studio is running on localhost:1234
    • Verify the model is loaded in LM Studio
    • Ensure no firewall is blocking the connection
    • Try refreshing the page if the issue persists
    """
  end

  defp troubleshooting_guidance(:connection, _) do
    """
    • Check your internet connection
    • Verify service endpoints are accessible
    • Try refreshing the page
    """
  end

  defp troubleshooting_guidance(:timeout, :chat) do
    """
    • The model may be processing a complex request
    • Try a simpler message to test connectivity
    • Check if LM Studio has sufficient resources
    • Consider using a smaller model if available
    """
  end

  defp troubleshooting_guidance(:timeout, _) do
    """
    • The operation may be taking longer than expected
    • Try again with a shorter timeout if possible
    • Check system resources and network connectivity
    """
  end

  defp troubleshooting_guidance(:validation, :agent) do
    """
    • Check agent configuration for required fields
    • Verify profile IDs exist and are properly configured
    • Ensure workflow references are valid
    """
  end

  defp troubleshooting_guidance(:seeding, _) do
    """
    • Check database connectivity
    • Verify required profiles exist (req_llm, embeddings_nomic_v15)
    • Ensure agent store is properly initialized
    """
  end

  defp troubleshooting_guidance(_, _), do: nil
end
