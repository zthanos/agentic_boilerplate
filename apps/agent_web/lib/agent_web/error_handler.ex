defmodule AgentWeb.ErrorHandler do
  @moduledoc """
  Centralized error handling and recovery strategies for the agent testing interface.

  Provides:
  - Error categorization and classification
  - User-friendly error message formatting
  - Context-aware recovery action suggestions
  - Consistent error reporting across components
  """

  @type error_type ::
          :connection | :timeout | :validation | :agent | :workflow | :seeding | :general
  @type error_context :: :agent_selection | :workflow | :chat | :seeding | :general
  @type recovery_action :: %{
          label: String.t(),
          event: String.t(),
          params: map()
        }

  @type error_info :: %{
          type: error_type(),
          context: error_context(),
          message: String.t(),
          original_error: term(),
          recovery_actions: [recovery_action()]
        }

  @doc """
  Analyzes an error and returns structured error information with recovery suggestions.

  ## Examples

      iex> AgentWeb.ErrorHandler.analyze_error("timeout after 30000ms", :chat)
      %{
        type: :timeout,
        context: :chat,
        message: "Request timed out after 30 seconds",
        original_error: "timeout after 30000ms",
        recovery_actions: [
          %{label: "Retry", event: "retry_last_message", params: %{}},
          %{label: "Check LM Studio", event: "check_lm_studio", params: %{}}
        ]
      }
  """
  @spec analyze_error(term(), error_context()) :: error_info()
  def analyze_error(error, context \\ :general)

  # Connection errors
  def analyze_error(error, context) when is_binary(error) do
    cond do
      String.contains?(error, "timeout") ->
        %{
          type: :timeout,
          context: context,
          message: format_timeout_error(error),
          original_error: error,
          recovery_actions: timeout_recovery_actions(context)
        }

      String.contains?(error, "connection") or String.contains?(error, "refused") ->
        %{
          type: :connection,
          context: context,
          message: format_connection_error(error),
          original_error: error,
          recovery_actions: connection_recovery_actions(context)
        }

      String.contains?(error, "validation") or String.contains?(error, "invalid") ->
        %{
          type: :validation,
          context: context,
          message: format_validation_error(error),
          original_error: error,
          recovery_actions: validation_recovery_actions(context)
        }

      String.contains?(error, "agent") ->
        %{
          type: :agent,
          context: context,
          message: format_agent_error(error),
          original_error: error,
          recovery_actions: agent_recovery_actions(context)
        }

      String.contains?(error, "workflow") ->
        %{
          type: :workflow,
          context: context,
          message: format_workflow_error(error),
          original_error: error,
          recovery_actions: workflow_recovery_actions(context)
        }

      String.contains?(error, "seed") ->
        %{
          type: :seeding,
          context: context,
          message: format_seeding_error(error),
          original_error: error,
          recovery_actions: seeding_recovery_actions(context)
        }

      true ->
        %{
          type: :general,
          context: context,
          message: format_general_error(error),
          original_error: error,
          recovery_actions: general_recovery_actions(context)
        }
    end
  end

  # Tuple errors (common in Elixir)
  def analyze_error({:error, reason}, context) do
    analyze_error(reason, context)
  end

  def analyze_error({:timeout, _}, context) do
    %{
      type: :timeout,
      context: context,
      message: "Operation timed out",
      original_error: {:timeout, context},
      recovery_actions: timeout_recovery_actions(context)
    }
  end

  # Atom errors
  def analyze_error(error, context) when is_atom(error) do
    error_string = Atom.to_string(error)
    analyze_error(error_string, context)
  end

  # Fallback for other error types
  def analyze_error(error, context) do
    %{
      type: :general,
      context: context,
      message: "An unexpected error occurred: #{inspect(error)}",
      original_error: error,
      recovery_actions: general_recovery_actions(context)
    }
  end

  @doc """
  Formats an error for user display, making technical errors more user-friendly.
  """
  @spec format_user_error(term()) :: String.t()
  def format_user_error(error) do
    error_info = analyze_error(error)
    error_info.message
  end

  # Private helper functions for error formatting

  defp format_timeout_error(error) do
    cond do
      String.contains?(error, "30000ms") or String.contains?(error, "30 seconds") ->
        "Request timed out after 30 seconds. The model may be processing a complex request."

      String.contains?(error, "ms") ->
        # Extract timeout value if possible
        timeout_ms = Regex.run(~r/(\d+)ms/, error)

        case timeout_ms do
          [_, ms] ->
            seconds = String.to_integer(ms) / 1000
            "Request timed out after #{seconds} seconds."

          _ ->
            "Request timed out. Please try again."
        end

      true ->
        "Request timed out. Please try again."
    end
  end

  defp format_connection_error(error) do
    cond do
      String.contains?(error, "1234") ->
        "Cannot connect to LM Studio (localhost:1234). Please ensure LM Studio is running and a model is loaded."

      String.contains?(error, "localhost") ->
        "Cannot connect to local service. Please check if the service is running."

      String.contains?(error, "refused") ->
        "Connection refused. The service may not be running or may be blocked by a firewall."

      true ->
        "Connection failed. Please check your network connection and try again."
    end
  end

  defp format_validation_error(error) do
    cond do
      String.contains?(error, "profile") ->
        "Invalid profile configuration. Please check that all required profiles exist."

      String.contains?(error, "agent") ->
        "Agent configuration is invalid. Please verify the agent settings."

      String.contains?(error, "workflow") ->
        "Workflow configuration is invalid. Please check the workflow definition."

      true ->
        "Validation failed: #{error}"
    end
  end

  defp format_agent_error(error) do
    cond do
      String.contains?(error, "not found") ->
        "Agent not found. The selected agent may have been removed or is unavailable."

      String.contains?(error, "execution") ->
        "Agent execution failed. There may be an issue with the agent configuration or the underlying model."

      true ->
        "Agent error: #{error}"
    end
  end

  defp format_workflow_error(error) do
    cond do
      String.contains?(error, "step") ->
        "Workflow step failed. Please check the workflow configuration and try again."

      String.contains?(error, "plan") ->
        "Workflow plan error. The workflow definition may be invalid or missing."

      true ->
        "Workflow error: #{error}"
    end
  end

  defp format_seeding_error(error) do
    cond do
      String.contains?(error, "profile") ->
        "Cannot seed agents: Required profiles are missing. Please ensure req_llm and embeddings_nomic_v15 profiles exist."

      String.contains?(error, "database") ->
        "Cannot seed agents: Database error. Please check database connectivity."

      true ->
        "Failed to create test agents: #{error}"
    end
  end

  defp format_general_error(error) do
    # Clean up common technical error patterns
    error
    # Remove markdown-style emphasis
    |> String.replace(~r/\*\*.*?\*\*/, "")
    # Remove map/tuple representations
    |> String.replace(~r/\{.*?\}/, "")
    # Remove list representations
    |> String.replace(~r/\[.*?\]/, "")
    |> String.trim()
    |> case do
      "" -> "An unexpected error occurred. Please try again."
      cleaned -> cleaned
    end
  end

  # Recovery action generators

  defp timeout_recovery_actions(:chat) do
    [
      %{label: "🔄 Retry", event: "retry_last_message", params: %{}},
      %{label: "🔧 Check LM Studio", event: "check_lm_studio_status", params: %{}},
      %{label: "💬 Try Simpler Message", event: "suggest_simple_message", params: %{}}
    ]
  end

  defp timeout_recovery_actions(_) do
    [
      %{label: "🔄 Retry", event: "retry_operation", params: %{}},
      %{label: "🔧 Check Status", event: "check_system_status", params: %{}}
    ]
  end

  defp connection_recovery_actions(:chat) do
    [
      %{label: "🔄 Retry Connection", event: "retry_last_message", params: %{}},
      %{label: "🚀 Start LM Studio", event: "open_lm_studio_guide", params: %{}},
      %{label: "🔧 Check Settings", event: "check_connection_settings", params: %{}}
    ]
  end

  defp connection_recovery_actions(_) do
    [
      %{label: "🔄 Retry", event: "retry_operation", params: %{}},
      %{label: "🔧 Check Connection", event: "check_connection", params: %{}}
    ]
  end

  defp validation_recovery_actions(:agent) do
    [
      %{label: "🔄 Reload Agent", event: "reload_agent", params: %{}},
      %{label: "🛠️ Check Profiles", event: "check_profiles", params: %{}},
      %{label: "🏠 Back to Selection", event: "back_to_agent_selection", params: %{}}
    ]
  end

  defp validation_recovery_actions(_) do
    [
      %{label: "🔄 Retry", event: "retry_operation", params: %{}},
      %{label: "🛠️ Check Configuration", event: "check_configuration", params: %{}}
    ]
  end

  defp agent_recovery_actions(_) do
    [
      %{label: "🔄 Retry", event: "retry_operation", params: %{}},
      %{label: "🔄 Reload Agent", event: "reload_agent", params: %{}},
      %{label: "🏠 Select Different Agent", event: "back_to_agent_selection", params: %{}}
    ]
  end

  defp workflow_recovery_actions(_) do
    [
      %{label: "🔄 Retry", event: "retry_operation", params: %{}},
      %{label: "🔄 Reload Workflow", event: "reload_workflow", params: %{}},
      %{label: "🏠 Back to Selection", event: "back_to_agent_selection", params: %{}}
    ]
  end

  defp seeding_recovery_actions(_) do
    [
      %{label: "🔄 Retry Seeding", event: "retry_seeding", params: %{}},
      %{label: "🛠️ Check Profiles", event: "check_profiles", params: %{}},
      %{label: "📚 Setup Guide", event: "open_setup_guide", params: %{}}
    ]
  end

  defp general_recovery_actions(_) do
    [
      %{label: "🔄 Retry", event: "retry_operation", params: %{}},
      %{label: "🔄 Refresh Page", event: "refresh_page", params: %{}}
    ]
  end
end
