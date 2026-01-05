defmodule AgentWebWeb.AdminProvidersLive do
  @moduledoc """
  Admin providers management LiveView for service provider management.
  Provides interface for provider CRUD operations, connection testing, and health monitoring.
  """
  use AgentWebWeb, :live_view
  alias AgentWebWeb.AdminLayouts
  alias AgentWeb.Providers

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to provider-related events
      Phoenix.PubSub.subscribe(AgentWeb.PubSub, "admin:providers")
    end

    {:ok,
     socket
     |> assign(:current_page, :providers)
     |> assign(:current_section, :management)
     |> assign(:sidebar_collapsed, false)
     |> assign(:page_title, "Service Providers")
     |> assign(:view_mode, :list)
     |> assign(:selected_provider, nil)
     # Use helper to ensure all filter assigns
     |> ensure_filter_assigns()
     |> assign(:selected_providers, [])
     |> assign(:show_bulk_actions, false)
     |> assign(:group_by_type, false)
     # Enhanced error handling and UX state
     |> assign(:loading, false)
     |> assign(:saving, false)
     |> assign(:deleting, false)
     |> assign(:testing_connection, false)
     |> assign(:testing_authentication, false)
     |> assign(:form_errors, %{})
     |> assign(:validation_errors, %{})
     |> assign(:auth_validation_errors, %{})
     |> assign(:auth_validation_status, nil)
     |> assign(:last_operation, nil)
     |> assign(:operation_status, nil)
     |> assign(:connection_test_result, nil)
     |> assign(:auth_test_result, nil)
     |> assign(:testing_all_connections, false)
     |> assign(:bulk_test_results, [])
     # Health monitoring state
     |> assign(:performing_health_check, false)
     |> assign(:performing_bulk_health_check, false)
     |> assign(:bulk_health_results, [])
     |> assign(:selected_health_metrics, nil)
     |> assign(:health_metrics_loading, false)
     |> assign(:aggregated_health_metrics, nil)
     # Analytics and statistics state
     |> assign(:provider_analytics, nil)
     |> assign(:analytics_loading, false)
     |> assign(:show_analytics_dashboard, false)
     |> assign(:analytics_view_mode, :overview)
     # Export functionality state
     |> assign(:last_export_data, nil)
     |> assign(:last_export_format, nil)
     |> assign(:export_loading, false)
     |> assign(:show_help, false)
     |> load_providers_data()
     |> load_health_metrics()}
  end

  @impl true
  def handle_event("toggle_sidebar", _params, socket) do
    new_state = !socket.assigns.sidebar_collapsed
    {:noreply, assign(socket, :sidebar_collapsed, new_state)}
  end

  @impl true
  def handle_event("set_sidebar_state", %{"collapsed" => collapsed}, socket) do
    {:noreply, assign(socket, :sidebar_collapsed, collapsed)}
  end

  @impl true
  def handle_event("search_providers", %{"search" => query}, socket) do
    {:noreply,
     socket
     |> assign(:search_query, query)
     |> filter_providers()}
  end

  @impl true
  def handle_event("filter_by_type", %{"type" => type}, socket) do
    {:noreply,
     socket
     |> assign(:type_filter, type)
     |> filter_providers()}
  end

  @impl true
  def handle_event("clear_filters", _params, socket) do
    {:noreply,
     socket
     |> assign(:search_query, "")
     |> assign(:type_filter, "all")
     |> assign(:status_filter, "all")
     |> assign(:enabled_filter, "all")
     |> filter_providers()}
  end

  @impl true
  def handle_event("filter_by_enabled", %{"enabled" => enabled}, socket) do
    {:noreply,
     socket
     |> assign(:enabled_filter, enabled)
     |> filter_providers()}
  end

  @impl true
  def handle_event("toggle_grouping", _params, socket) do
    # Χρησιμοποιεί το existing assign
    new_grouping = !socket.assigns.group_by_type

    {:noreply,
     socket
     |> assign(:group_by_type, new_grouping)
     |> filter_providers()}
  end

  @impl true
  def handle_event("provider_type_changed", %{"provider" => %{"type" => type}}, socket) do
    # Handle provider type change to show/hide type-specific fields
    updated_provider =
      socket.assigns.selected_provider
      |> Map.put(:type, convert_string_to_provider_type(type))

    {:noreply,
     socket
     |> assign(:selected_provider, updated_provider)
     |> assign(:form_errors, %{})
     |> assign(:validation_errors, %{})}
  end

  @impl true
  def handle_event("filter_by_status", %{"status" => status}, socket) do
    {:noreply,
     socket
     |> assign(:status_filter, status)
     |> filter_providers()}
  end

  @impl true
  def handle_event("view_provider", %{"provider_id" => provider_id}, socket) do
    provider = Enum.find(socket.assigns.all_providers, &(&1.id == provider_id))

    {:noreply,
     socket
     |> assign(:selected_provider, provider)
     |> assign(:view_mode, :detail)}
  end

  @impl true
  def handle_event("edit_provider", %{"provider_id" => provider_id}, socket) do
    provider = Enum.find(socket.assigns.all_providers, &(&1.id == provider_id))

    {:noreply,
     socket
     |> assign(:selected_provider, provider)
     |> assign(:view_mode, :edit)
     |> assign(:form_errors, %{})
     |> assign(:validation_errors, %{})
     |> assign(:saving, false)}
  end

  @impl true
  def handle_event("create_provider", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_provider, get_empty_provider())
     |> assign(:view_mode, :create)
     |> assign(:form_errors, %{})
     |> assign(:validation_errors, %{})
     |> assign(:saving, false)}
  end

  @impl true
  def handle_event("back_to_list", _params, socket) do
    {:noreply,
     socket
     |> assign(:view_mode, :list)
     |> assign(:selected_provider, nil)
     |> assign(:form_errors, %{})
     |> assign(:validation_errors, %{})
     |> assign(:saving, false)
     |> assign(:deleting, false)
     |> assign(:connection_test_result, nil)}
  end

  @impl true
  def handle_event("validate_provider", %{"provider" => provider_params}, socket) do
    # Real-time form validation without saving
    case validate_form_params(provider_params) do
      {:ok, _attrs} ->
        {:noreply,
         socket
         |> assign(:form_errors, %{})
         |> assign(:validation_errors, %{})}

      {:error, validation_errors} when is_list(validation_errors) ->
        # Convert list of errors to field-specific map
        error_map = build_error_map(validation_errors)

        {:noreply,
         socket
         |> assign(:form_errors, error_map)
         |> assign(:validation_errors, error_map)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:form_errors, %{general: reason})
         |> assign(:validation_errors, %{general: reason})}
    end
  end

  @impl true
  def handle_event("save_provider", %{"provider" => provider_params}, socket) do
    # Set loading state immediately
    socket = assign(socket, :saving, true)

    # Log the save attempt (without sensitive data)
    operation_type = if socket.assigns.view_mode == :create, do: "create", else: "update"
    provider_name = provider_params["name"] || "Unknown"

    Providers.secure_log(:info, "Provider save attempt", %{
      operation: operation_type,
      provider_name: provider_name,
      view_mode: socket.assigns.view_mode,
      has_auth_config: has_authentication_config?(provider_params)
    })

    # Attempt to save the provider using the context module
    result =
      case socket.assigns.view_mode do
        :create ->
          Providers.create_provider(provider_params)

        :edit ->
          provider_id = socket.assigns.selected_provider.id
          Providers.update_provider(provider_id, provider_params)
      end

    case result do
      {:ok, _provider_id} when socket.assigns.view_mode == :create ->
        # Log successful creation
        Providers.audit_log("provider_created", %{
          provider_name: provider_name,
          operation: "create_provider"
        })

        {:noreply,
         socket
         |> assign(:view_mode, :list)
         |> assign(:selected_provider, nil)
         |> assign(:saving, false)
         |> assign(:form_errors, %{})
         |> assign(:validation_errors, %{})
         |> assign(:last_operation, "create")
         |> assign(:operation_status, :success)
         |> put_flash(:info, build_success_message("created", provider_params["name"]))
         |> load_providers_data()}

      {:ok, _provider} when socket.assigns.view_mode == :edit ->
        # Log successful update
        Providers.audit_log("provider_updated", %{
          provider_id: socket.assigns.selected_provider.id,
          provider_name: provider_name,
          operation: "update_provider"
        })

        {:noreply,
         socket
         |> assign(:view_mode, :list)
         |> assign(:selected_provider, nil)
         |> assign(:saving, false)
         |> assign(:form_errors, %{})
         |> assign(:validation_errors, %{})
         |> assign(:last_operation, "update")
         |> assign(:operation_status, :success)
         |> put_flash(:info, build_success_message("updated", provider_params["name"]))
         |> load_providers_data()}

      {:error, reason} when is_binary(reason) ->
        # Log save failure
        Providers.secure_log(:error, "Provider save failed", %{
          operation: operation_type,
          provider_name: provider_name,
          reason: reason
        })

        {:noreply,
         socket
         |> assign(:saving, false)
         |> assign(:last_operation, "save")
         |> assign(:operation_status, :error)
         |> put_flash(:error, build_error_message("save", reason))}

      {:error, reason} ->
        # Log save failure with complex reason
        Providers.secure_log(:error, "Provider save failed", %{
          operation: operation_type,
          provider_name: provider_name,
          reason: "Complex error - see logs"
        })

        {:noreply,
         socket
         |> assign(:saving, false)
         |> assign(:last_operation, "save")
         |> assign(:operation_status, :error)
         |> put_flash(:error, build_error_message("save", inspect(reason)))}
    end
  end

  @impl true
  def handle_event("delete_provider", %{"provider_id" => provider_id}, socket) do
    # Set deleting state
    socket = assign(socket, :deleting, true)

    # Get provider name for better error messages
    provider = Enum.find(socket.assigns.all_providers, &(&1.id == provider_id))
    provider_name = if provider, do: provider.name, else: "Unknown Provider"

    # Log deletion attempt for audit trail
    Providers.audit_log("provider_deletion_attempt", %{
      provider_id: provider_id,
      provider_name: provider_name,
      operation: "delete_provider"
    })

    case Providers.delete_provider(provider_id) do
      :ok ->
        # Log successful deletion
        Providers.audit_log("provider_deleted", %{
          provider_id: provider_id,
          provider_name: provider_name,
          operation: "delete_provider_success"
        })

        {:noreply,
         socket
         |> assign(:deleting, false)
         |> assign(:last_operation, "delete")
         |> assign(:operation_status, :success)
         |> put_flash(:info, build_success_message("deleted", provider_name))
         |> load_providers_data()}

      {:error, reason} ->
        # Log deletion failure
        Providers.secure_log(:error, "Provider deletion failed", %{
          provider_id: provider_id,
          provider_name: provider_name,
          reason: reason
        })

        {:noreply,
         socket
         |> assign(:deleting, false)
         |> assign(:last_operation, "delete")
         |> assign(:operation_status, :error)
         |> put_flash(:error, build_error_message("delete", reason, provider_name))}
    end
  end

  @impl true
  def handle_event("toggle_status", %{"provider_id" => provider_id}, socket) do
    # Get provider for better messages
    provider = Enum.find(socket.assigns.all_providers, &(&1.id == provider_id))
    provider_name = if provider, do: provider.name, else: "Unknown Provider"
    new_status = !provider.enabled

    case Providers.set_provider_enabled(provider_id, new_status) do
      {:ok, _updated_provider} ->
        status = if new_status, do: "enabled", else: "disabled"

        {:noreply,
         socket
         |> assign(:last_operation, "toggle_status")
         |> assign(:operation_status, :success)
         |> put_flash(:info, build_success_message(status, provider_name))
         |> load_providers_data()}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:last_operation, "toggle_status")
         |> assign(:operation_status, :error)
         |> put_flash(:error, build_error_message("toggle status", reason, provider_name))}
    end
  end

  @impl true
  def handle_event("test_connection", %{"provider_id" => provider_id}, socket) do
    # Set testing state with provider-specific loading
    socket = assign(socket, :testing_connection, provider_id)

    # Get provider name for better error messages
    provider = Enum.find(socket.assigns.all_providers, &(&1.id == provider_id))
    provider_name = if provider, do: provider.name, else: "Unknown Provider"

    case Providers.test_provider_connection(provider_id) do
      {:ok, test_result} ->
        # Determine flash message based on overall test status
        {flash_type, flash_message} =
          case test_result.overall_status do
            :success ->
              {:info,
               "✅ Connection test successful for '#{provider_name}'! All tests passed in #{test_result.response_time_ms}ms"}

            :warning ->
              {:warning,
               "⚠️ Connection test for '#{provider_name}' completed with warnings. Some issues detected - check the detailed results below."}

            _ ->
              {:error,
               "❌ Connection test failed for '#{provider_name}'. Check the detailed results and troubleshooting hints below."}
          end

        {:noreply,
         socket
         |> assign(:testing_connection, false)
         |> assign(:connection_test_result, enhance_test_result(test_result, provider_name))
         |> assign(:last_operation, "test_connection")
         |> assign(:operation_status, test_result.overall_status)
         |> put_flash(flash_type, flash_message)}

      {:error, reason} ->
        error_result = %{
          overall_status: :error,
          provider_name: provider_name,
          error_details: [reason],
          troubleshooting_hints: get_connection_troubleshooting_hints(reason),
          response_time_ms: nil,
          tests: %{},
          timestamp: DateTime.utc_now()
        }

        {:noreply,
         socket
         |> assign(:testing_connection, false)
         |> assign(:connection_test_result, error_result)
         |> assign(:last_operation, "test_connection")
         |> assign(:operation_status, :error)
         |> put_flash(:error, build_error_message("connection_test", reason, provider_name))}
    end
  end

  @impl true
  def handle_event("test_authentication", %{"provider_id" => provider_id}, socket) do
    # Set testing state with provider-specific loading
    socket = assign(socket, :testing_authentication, provider_id)

    # Get provider name for better error messages
    provider = Enum.find(socket.assigns.all_providers, &(&1.id == provider_id))
    provider_name = if provider, do: provider.name, else: "Unknown Provider"

    case Providers.test_provider_authentication(provider_id) do
      {:ok, %{status: :success, message: message}} ->
        enhanced_result = %{
          status: :success,
          message: message,
          provider_name: provider_name,
          timestamp: DateTime.utc_now(),
          details: "Authentication credentials verified successfully"
        }

        {:noreply,
         socket
         |> assign(:testing_authentication, false)
         |> assign(:auth_test_result, enhanced_result)
         |> assign(:last_operation, "test_authentication")
         |> assign(:operation_status, :success)
         |> put_flash(
           :info,
           "✅ Authentication test successful for '#{provider_name}': #{message}"
         )}

      {:ok, %{status: :no_auth, message: message}} ->
        enhanced_result = %{
          status: :info,
          message: message,
          provider_name: provider_name,
          timestamp: DateTime.utc_now(),
          details: "No authentication configured for this provider"
        }

        {:noreply,
         socket
         |> assign(:testing_authentication, false)
         |> assign(:auth_test_result, enhanced_result)
         |> assign(:last_operation, "test_authentication")
         |> assign(:operation_status, :success)
         |> put_flash(:info, "ℹ️ #{message} for '#{provider_name}'")}

      {:error, reason} ->
        enhanced_result = %{
          status: :error,
          message: reason,
          provider_name: provider_name,
          timestamp: DateTime.utc_now(),
          troubleshooting_hints: get_auth_troubleshooting_hints(reason),
          details: "Authentication verification failed"
        }

        {:noreply,
         socket
         |> assign(:testing_authentication, false)
         |> assign(:auth_test_result, enhanced_result)
         |> assign(:last_operation, "test_authentication")
         |> assign(:operation_status, :error)
         |> put_flash(:error, build_error_message("authentication_test", reason, provider_name))}
    end
  end

  @impl true
  def handle_event("test_all_connections", _params, socket) do
    # Set testing state for all providers
    socket = assign(socket, :testing_all_connections, true)

    # Get all enabled providers
    enabled_providers = Enum.filter(socket.assigns.all_providers, & &1.enabled)

    if Enum.empty?(enabled_providers) do
      {:noreply,
       socket
       |> assign(:testing_all_connections, false)
       |> put_flash(:warning, "No enabled providers to test")}
    else
      # Start async testing of all providers
      test_results = test_multiple_providers_async(enabled_providers)

      # Count results
      successful_tests =
        Enum.count(test_results, fn {_id, result} ->
          match?({:ok, %{overall_status: :success}}, result)
        end)

      total_tests = length(test_results)

      {:noreply,
       socket
       |> assign(:testing_all_connections, false)
       |> assign(:bulk_test_results, test_results)
       |> assign(:last_operation, "test_all_connections")
       |> assign(
         :operation_status,
         if(successful_tests == total_tests, do: :success, else: :warning)
       )
       |> put_flash(
         :info,
         "Bulk connection test completed: #{successful_tests}/#{total_tests} providers successful"
       )
       |> load_providers_data()}
    end
  end

  @impl true
  def handle_event("perform_health_check", %{"provider_id" => provider_id}, socket) do
    # Set health check state
    socket = assign(socket, :performing_health_check, true)

    case Providers.perform_health_check(provider_id) do
      {:ok, health_result} ->
        # Get provider name for better messages
        provider = Enum.find(socket.assigns.all_providers, &(&1.id == provider_id))
        provider_name = if provider, do: provider.name, else: "Unknown Provider"

        {flash_type, flash_message} =
          case health_result.status do
            :online ->
              {:info, "Health check successful for '#{provider_name}' - Provider is online"}

            :degraded ->
              {:warning, "Health check completed for '#{provider_name}' - Provider is degraded"}

            :offline ->
              {:error, "Health check failed for '#{provider_name}' - Provider is offline"}

            _ ->
              {:warning, "Health check completed for '#{provider_name}' - Status unknown"}
          end

        {:noreply,
         socket
         |> assign(:performing_health_check, false)
         |> assign(:last_operation, "health_check")
         |> assign(:operation_status, health_result.status)
         |> put_flash(flash_type, flash_message)
         |> load_providers_data()}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:performing_health_check, false)
         |> assign(:last_operation, "health_check")
         |> assign(:operation_status, :error)
         |> put_flash(:error, "Health check failed: #{reason}")
         |> load_providers_data()}
    end
  end

  @impl true
  def handle_event("perform_bulk_health_check", _params, socket) do
    # Set bulk health check state
    socket = assign(socket, :performing_bulk_health_check, true)

    case Providers.perform_bulk_health_check() do
      {:ok, health_results} ->
        # Count results
        successful_checks =
          Enum.count(health_results, fn {_id, result} ->
            match?({:ok, %{status: :online}}, result)
          end)

        total_checks = length(health_results)

        {:noreply,
         socket
         |> assign(:performing_bulk_health_check, false)
         |> assign(:bulk_health_results, health_results)
         |> assign(:last_operation, "bulk_health_check")
         |> assign(
           :operation_status,
           if(successful_checks == total_checks, do: :success, else: :warning)
         )
         |> put_flash(
           :info,
           "Bulk health check completed: #{successful_checks}/#{total_checks} providers online"
         )
         |> load_providers_data()}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:performing_bulk_health_check, false)
         |> assign(:last_operation, "bulk_health_check")
         |> assign(:operation_status, :error)
         |> put_flash(:error, "Bulk health check failed: #{reason}")
         |> load_providers_data()}
    end
  end

  @impl true
  def handle_event(
        "update_health_status",
        %{"provider_id" => provider_id, "status" => status},
        socket
      ) do
    # Manual health status update
    health_status = String.to_existing_atom(status)

    case Providers.update_provider_health_status(provider_id, health_status) do
      {:ok, _updated_provider} ->
        provider = Enum.find(socket.assigns.all_providers, &(&1.id == provider_id))
        provider_name = if provider, do: provider.name, else: "Unknown Provider"

        {:noreply,
         socket
         |> assign(:last_operation, "update_health_status")
         |> assign(:operation_status, :success)
         |> put_flash(:info, "Health status updated for '#{provider_name}' to #{status}")
         |> load_providers_data()}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:last_operation, "update_health_status")
         |> assign(:operation_status, :error)
         |> put_flash(:error, "Failed to update health status: #{reason}")
         |> load_providers_data()}
    end
  end

  @impl true
  def handle_event("view_health_metrics", %{"provider_id" => provider_id}, socket) do
    case Providers.get_provider_health_metrics(provider_id) do
      {:ok, health_metrics} ->
        {:noreply,
         socket
         |> assign(:selected_health_metrics, health_metrics)
         |> assign(:view_mode, :health_metrics)}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to load health metrics: #{reason}")}
    end
  end

  @impl true
  def handle_event("validate_authentication", %{"provider" => provider_params}, socket) do
    # Real-time authentication validation
    case Providers.validate_authentication_config(provider_params) do
      :ok ->
        {:noreply,
         socket
         |> assign(:auth_validation_errors, %{})
         |> assign(:auth_validation_status, :valid)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:auth_validation_errors, %{general: reason})
         |> assign(:auth_validation_status, :invalid)}
    end
  end

  @impl true
  def handle_event("toggle_analytics_dashboard", _params, socket) do
    new_state = !socket.assigns.show_analytics_dashboard
    {:noreply, assign(socket, :show_analytics_dashboard, new_state)}
  end

  @impl true
  def handle_event("set_analytics_view", %{"view" => view}, socket) do
    view_atom = String.to_existing_atom(view)
    {:noreply, assign(socket, :analytics_view_mode, view_atom)}
  rescue
    ArgumentError ->
      {:noreply, socket}
  end

  @impl true
  def handle_event("refresh_analytics", _params, socket) do
    socket = assign(socket, :analytics_loading, true)

    case Providers.get_provider_analytics() do
      {:ok, analytics} ->
        {:noreply,
         socket
         |> assign(:provider_analytics, analytics)
         |> assign(:analytics_loading, false)
         |> put_flash(:info, "Analytics refreshed successfully")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:analytics_loading, false)
         |> put_flash(:error, "Failed to refresh analytics: #{reason}")}
    end
  end

  @impl true
  def handle_event("export_providers", %{"format" => format}, socket) do
    export_opts = [
      format: String.to_existing_atom(format),
      include_disabled: false,
      mask_credentials: true
    ]

    case Providers.export_providers_secure(export_opts) do
      {:ok, export_data} ->
        # In a real implementation, you might want to:
        # 1. Store the export file temporarily
        # 2. Provide a download link
        # 3. Send via email for large exports

        {:noreply,
         socket
         |> put_flash(:info, "Provider export completed successfully in #{format} format")
         |> assign(:last_export_data, export_data)
         |> assign(:last_export_format, format)}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Export failed: #{reason}")}
    end
  rescue
    ArgumentError ->
      {:noreply,
       socket
       |> put_flash(:error, "Invalid export format specified")}
  end

  @impl true
  def handle_event("export_providers_with_options", params, socket) do
    format = String.to_existing_atom(Map.get(params, "format", "json"))
    include_disabled = Map.get(params, "include_disabled") == "true"
    mask_credentials = Map.get(params, "mask_credentials", "true") == "true"

    export_opts = [
      format: format,
      include_disabled: include_disabled,
      mask_credentials: mask_credentials
    ]

    case Providers.export_providers_secure(export_opts) do
      {:ok, export_data} ->
        {:noreply,
         socket
         |> put_flash(:info, "Provider export completed successfully")
         |> assign(:last_export_data, export_data)
         |> assign(:last_export_format, format)}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Export failed: #{reason}")}
    end
  rescue
    ArgumentError ->
      {:noreply,
       socket
       |> put_flash(:error, "Invalid export format specified")}
  end

  @impl true
  def handle_event("toggle_help", _params, socket) do
    new_state = !Map.get(socket.assigns, :show_help, false)
    {:noreply, assign(socket, :show_help, new_state)}
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
    assigns =
      if is_nil(assigns[:available_provider_types]) do
        assign(assigns, :available_provider_types, Providers.get_available_provider_types())
      else
        assigns
      end

    assigns =
      if is_nil(assigns[:available_auth_types]) do
        assign(assigns, :available_auth_types, Providers.get_available_auth_types())
      else
        assigns
      end

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
          LLM Providers
          <:subtitle>Manage LLM model providers settings</:subtitle>

          <:actions>
            <div class="flex gap-2">
              <button
                :if={@view_mode == :list}
                class="btn btn-primary btn-sm"
                phx-click="create_provider"
              >
                <.icon name="hero-plus" class="size-4 mr-2" /> New Providers
              </button>
              <button
                :if={@view_mode != :list}
                class="btn btn-outline btn-sm"
                phx-click="back_to_list"
              >
                <.icon name="hero-arrow-left" class="size-4 mr-2" /> Back to List
              </button>
            </div>
          </:actions>
        </.header>
      </div>
      <div class="flex flex-col flex-1 overflow-hidden" id="admin-providers-container" phx-hook="GlobalHelpHandler">
        <!-- Enhanced Flash Messages -->
        <.enhanced_flash
          flash={@flash}
          last_operation={@last_operation}
          operation_status={@operation_status}
        />

        <!-- Main Content Area -->
        <div class="flex-1 overflow-hidden">
          <%= case @view_mode do %>
            <% :list -> %>
              <div class="h-full">
                <.providers_list
                  providers={@filtered_providers}
                  search_query={@search_query}
                  type_filter={@type_filter}
                  status_filter={@status_filter}
                  enabled_filter={@enabled_filter}
                  provider_stats={@provider_stats}
                  loading={@loading}
                  deleting={@deleting}
                  testing_connection={@testing_connection}
                  performing_health_check={@performing_health_check}
                  group_by_type={@group_by_type}
                />
              </div>
            <% :detail -> %>
              <div class="h-full p-6">
                <div class="flex items-center justify-between mb-6">
                  <h1 class="text-2xl font-bold">Provider Details</h1>

                  <button
                    class="btn btn-ghost btn-sm"
                    phx-click="back_to_list"
                  >
                    <.icon name="hero-arrow-left" class="size-4 mr-2" /> Back to List
                  </button>
                </div>

                <.provider_detail
                  provider={@selected_provider}
                  connection_test_result={@connection_test_result}
                  testing_connection={@testing_connection}
                  performing_health_check={@performing_health_check}
                />
              </div>
            <% mode when mode in [:create, :edit] -> %>
              <div class="h-full p-6">
                <div class="flex items-center justify-between mb-6">
                  <h1 class="text-2xl font-bold">
                    {if @view_mode == :create, do: "Create Provider", else: "Edit Provider"}
                  </h1>

                  <button
                    class="btn btn-ghost btn-sm"
                    phx-click="back_to_list"
                  >
                    <.icon name="hero-arrow-left" class="size-4 mr-2" /> Back to List
                  </button>
                </div>

                <.provider_form
                  provider={@selected_provider}
                  mode={@view_mode}
                  available_provider_types={@available_provider_types}
                  available_auth_types={@available_auth_types}
                  saving={@saving}
                  form_errors={@form_errors}
                  validation_errors={@validation_errors}
                />
              </div>
            <% :health_metrics -> %>
              <div class="h-full p-6">
                <div class="flex items-center justify-between mb-6">
                  <h1 class="text-2xl font-bold">Health Metrics</h1>

                  <button
                    class="btn btn-ghost btn-sm"
                    phx-click="back_to_list"
                  >
                    <.icon name="hero-arrow-left" class="size-4 mr-2" /> Back to List
                  </button>
                </div>
                 <.health_dashboard metrics={@selected_health_metrics} />
              </div>
            <% _ -> %>
              <div class="h-full p-6">
                <div class="text-center py-12">
                  <.icon name="hero-exclamation-triangle" class="size-16 text-warning mx-auto mb-4" />
                  <h2 class="text-xl font-semibold mb-2">Unknown View Mode</h2>

                  <p class="text-base-content/70 mb-4">The requested view mode is not supported.</p>

                  <button class="btn btn-primary" phx-click="back_to_list">
                    Return to Provider List
                  </button>
                </div>
              </div>
          <% end %>
        </div>

        <!-- Help Button -->
        <div class="fixed bottom-6 left-6 z-40">
          <button
            class="btn btn-info btn-circle shadow-lg hover:shadow-xl transition-all duration-200"
            phx-click="toggle_help"
            title="Show Help & Documentation (F1)"
          >
            <.icon name="hero-question-mark-circle" class="size-6" />
          </button>
        </div>
        <!-- Bulk Actions Toolbar (when providers are selected) -->
        <div
          :if={@show_bulk_actions && length(@selected_providers) > 0}
          class="fixed bottom-20 left-1/2 transform -translate-x-1/2 z-40"
        >
          <div class="bg-base-100 shadow-xl rounded-lg p-4 border">
            <div class="flex items-center gap-4">
              <span class="text-sm font-medium">
                {length(@selected_providers)} provider(s) selected
              </span>
              <div class="flex gap-2">
                <button
                  class="btn btn-success btn-sm"
                  phx-click="test_all_connections"
                  disabled={@testing_all_connections}
                >
                  <.icon name="hero-signal" class="size-4 mr-1" /> Test All
                </button>
                <button
                  class="btn btn-info btn-sm"
                  phx-click="perform_bulk_health_check"
                  disabled={@performing_bulk_health_check}
                >
                  <.icon name="hero-heart" class="size-4 mr-1" /> Health Check
                </button>
                <button
                  class="btn btn-ghost btn-sm"
                  phx-click="clear_selection"
                >
                  <.icon name="hero-x-mark" class="size-4 mr-1" /> Clear
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
      <!-- Comprehensive Help Modal -->
      <.comprehensive_help show_help={@show_help} />
      <!-- Analytics Dashboard Modal -->
      <div
        :if={@show_analytics_dashboard}
        class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm"
      >
        <div class="modal-box max-w-7xl max-h-[90vh] overflow-y-auto">
          <div class="flex items-center justify-between mb-6">
            <h2 class="text-2xl font-bold">Provider Analytics Dashboard</h2>

            <button class="btn btn-ghost btn-sm" phx-click="toggle_analytics_dashboard">
              <.icon name="hero-x-mark" class="size-5" />
            </button>
          </div>

          <.analytics_dashboard
            analytics={@provider_analytics}
            view_mode={@analytics_view_mode}
            loading={@analytics_loading}
          />
        </div>
      </div>
    </AdminLayouts.admin>
    """
  end

  # Load providers data using context module with proper filtering
  defp load_providers_data(socket) do
    # Ensure all filter assigns are present
    socket = ensure_filter_assigns(socket)

    # Set loading state
    socket = assign(socket, :loading, true)

    filters = build_filters(socket)

    case Providers.list_providers_ui(filters) do
      {:ok, ui_providers} ->
        # Load basic statistics
        stats_result = Providers.get_provider_statistics()

        # Load enhanced analytics
        analytics_result = Providers.get_dashboard_statistics()

        case {stats_result, analytics_result} do
          {{:ok, stats}, {:ok, analytics}} ->
            socket
            |> assign(:all_providers, ui_providers)
            |> assign(:filtered_providers, ui_providers)
            # Add this for template compatibility
            |> assign(:providers, ui_providers)
            |> assign(:provider_stats, stats)
            |> assign(:provider_analytics, analytics)
            |> assign(:loading, false)

          {{:ok, stats}, {:error, _}} ->
            socket
            |> assign(:all_providers, ui_providers)
            |> assign(:filtered_providers, ui_providers)
            # Add this for template compatibility
            |> assign(:providers, ui_providers)
            |> assign(:provider_stats, stats)
            |> assign(:provider_analytics, build_empty_analytics())
            |> assign(:loading, false)

          {{:error, _}, _} ->
            socket
            |> assign(:all_providers, ui_providers)
            |> assign(:filtered_providers, ui_providers)
            # Add this for template compatibility
            |> assign(:providers, ui_providers)
            |> assign(:provider_stats, build_empty_stats())
            |> assign(:provider_analytics, build_empty_analytics())
            |> assign(:loading, false)
        end

      {:error, reason} ->
        socket
        |> assign(:all_providers, [])
        |> assign(:filtered_providers, [])
        # Add this for template compatibility
        |> assign(:providers, [])
        |> assign(:provider_stats, build_empty_stats())
        |> assign(:provider_analytics, build_empty_analytics())
        |> assign(:loading, false)
        |> assign(:last_operation, "load")
        |> assign(:operation_status, :error)
        |> put_flash(:error, build_error_message("load providers", reason))
    end
  end

  # Load aggregated health metrics
  defp load_health_metrics(socket) do
    socket = assign(socket, :health_metrics_loading, true)

    case Providers.get_aggregated_health_metrics() do
      {:ok, metrics} ->
        socket
        |> assign(:aggregated_health_metrics, metrics)
        |> assign(:health_metrics_loading, false)

      {:error, _reason} ->
        socket
        |> assign(:aggregated_health_metrics, build_empty_health_metrics())
        |> assign(:health_metrics_loading, false)
    end
  end

  # Build empty health metrics structure
  defp build_empty_health_metrics do
    %{
      total_providers: 0,
      enabled_providers: 0,
      health_distribution: %{
        online: 0,
        degraded: 0,
        offline: 0,
        unknown: 0
      },
      health_percentages: %{
        online: 0.0,
        degraded: 0.0,
        offline: 0.0,
        unknown: 0.0
      },
      average_response_time_ms: nil,
      system_health_score: 0.0,
      last_updated: DateTime.utc_now()
    }
  end

  # Enhanced filtering with improved search across name, description, and URLs
  defp filter_providers(socket) do
    # Since the context module already handles filtering, we just need to reload with new filters
    load_providers_data(socket)
  end

  # Build comprehensive filters for the context module
  defp build_filters(socket) do
    %{
      search_query: socket.assigns[:search_query] || "",
      type_filter: socket.assigns[:type_filter] || "all",
      status_filter: socket.assigns[:status_filter] || "all",
      enabled_filter: socket.assigns[:enabled_filter] || "all",
      group_by_type: socket.assigns[:group_by_type] || false
    }
  end

  # Ensure all filter assigns are present
  defp ensure_filter_assigns(socket) do
    socket
    |> assign_new(:search_query, fn -> "" end)
    |> assign_new(:type_filter, fn -> "all" end)
    |> assign_new(:status_filter, fn -> "all" end)
    |> assign_new(:enabled_filter, fn -> "all" end)
    |> assign_new(:group_by_type, fn -> false end)
  end

  # Build empty statistics structure
  defp build_empty_stats do
    %{
      total: 0,
      enabled: 0,
      disabled: 0,
      by_type: %{},
      by_health: %{}
    }
  end

  # Build empty analytics structure
  defp build_empty_analytics do
    %{
      basic_stats: build_empty_stats(),
      usage_analytics: %{
        total_providers: 0,
        active_providers: 0,
        utilization_rate: 0.0,
        type_distribution: %{},
        auth_method_usage: %{},
        health_trends: %{},
        config_completeness: %{}
      },
      cost_analytics: %{
        total_subscription_cost: 0.0,
        token_based_count: 0,
        request_based_count: 0,
        subscription_count: 0,
        cost_by_type: %{},
        avg_token_cost: 0.0,
        avg_request_cost: 0.0,
        cost_efficiency: 0.0
      },
      performance_metrics: %{
        avg_response_time: nil,
        min_response_time: nil,
        max_response_time: nil,
        uptime_percentage: 0.0,
        error_rate: 0.0,
        performance_by_type: %{},
        health_distribution: %{},
        performance_trends: %{}
      },
      trends: %{
        recent_additions: 0,
        health_changes: %{},
        recent_updates: 0,
        growth_metrics: %{},
        usage_patterns: %{}
      },
      last_updated: DateTime.utc_now()
    }
  end

  # Validate form parameters without saving (for real-time validation)
  defp validate_form_params(params) do
    errors = []

    # Basic validation
    errors =
      if is_nil(params["name"]) or String.trim(params["name"]) == "" do
        ["name: Name is required" | errors]
      else
        errors
      end

    errors =
      if is_nil(params["type"]) or params["type"] == "" do
        ["type: Provider type is required" | errors]
      else
        errors
      end

    # Provider type specific validation
    provider_type = convert_string_to_provider_type(params["type"])

    errors =
      case validate_provider_type_requirements(params, provider_type) do
        :ok -> errors
        {:error, type_errors} -> type_errors ++ errors
      end

    # URL validation
    errors =
      if params["base_url"] && params["base_url"] != "" do
        case URI.parse(params["base_url"]) do
          %URI{scheme: scheme} when scheme in ["http", "https"] -> errors
          _ -> ["base_url: Invalid URL format" | errors]
        end
      else
        errors
      end

    # Timeout validation
    errors = validate_timeout_param(params["request_timeout_ms"], "request_timeout_ms", errors)

    errors =
      validate_timeout_param(params["connection_timeout_ms"], "connection_timeout_ms", errors)

    errors = validate_timeout_param(params["read_timeout_ms"], "read_timeout_ms", errors)

    # Numeric validation
    errors = validate_numeric_param(params["retries"], "retries", 0, 10, errors)

    errors =
      validate_numeric_param(params["retry_backoff_ms"], "retry_backoff_ms", 100, 10000, errors)

    errors =
      validate_numeric_param(params["requests_per_minute"], "requests_per_minute", 1, nil, errors)

    errors =
      validate_numeric_param(params["requests_per_hour"], "requests_per_hour", 1, nil, errors)

    errors =
      validate_numeric_param(
        params["concurrent_connections"],
        "concurrent_connections",
        1,
        nil,
        errors
      )

    # JSON validation
    errors = validate_json_param(params["default_headers"], "default_headers", errors)
    errors = validate_json_param(params["custom_params"], "custom_params", errors)
    errors = validate_json_param(params["oauth2_config"], "oauth2_config", errors)
    errors = validate_json_param(params["custom_auth_headers"], "custom_auth_headers", errors)

    # Cost validation
    errors =
      validate_cost_param(params["input_token_cost_per_1k"], "input_token_cost_per_1k", errors)

    errors =
      validate_cost_param(params["output_token_cost_per_1k"], "output_token_cost_per_1k", errors)

    errors = validate_cost_param(params["request_cost"], "request_cost", errors)
    errors = validate_cost_param(params["monthly_subscription"], "monthly_subscription", errors)

    if Enum.empty?(errors) do
      {:ok, params}
    else
      {:error, errors}
    end
  end

  defp validate_timeout_param(nil, _field, errors), do: errors
  defp validate_timeout_param("", _field, errors), do: errors

  defp validate_timeout_param(value, field, errors) when is_binary(value) do
    case Integer.parse(value) do
      {timeout, ""} when timeout > 0 and timeout <= 300_000 -> errors
      _ -> ["#{field}: Must be a positive integer between 1 and 300000" | errors]
    end
  end

  defp validate_timeout_param(value, field, errors) when is_integer(value) do
    if value > 0 and value <= 300_000 do
      errors
    else
      ["#{field}: Must be between 1 and 300000" | errors]
    end
  end

  defp validate_timeout_param(_, field, errors), do: ["#{field}: Invalid timeout value" | errors]

  defp validate_numeric_param(nil, _field, _min, _max, errors), do: errors
  defp validate_numeric_param("", _field, _min, _max, errors), do: errors

  defp validate_numeric_param(value, field, min, max, errors) when is_binary(value) do
    case Integer.parse(value) do
      {num, ""} -> validate_numeric_range(num, field, min, max, errors)
      _ -> ["#{field}: Must be a valid number" | errors]
    end
  end

  defp validate_numeric_param(value, field, min, max, errors) when is_integer(value) do
    validate_numeric_range(value, field, min, max, errors)
  end

  defp validate_numeric_param(_, field, _min, _max, errors),
    do: ["#{field}: Invalid numeric value" | errors]

  defp validate_numeric_range(num, field, min, max, errors) do
    cond do
      min && num < min -> ["#{field}: Must be at least #{min}" | errors]
      max && num > max -> ["#{field}: Must be at most #{max}" | errors]
      true -> errors
    end
  end

  defp validate_json_param(nil, _field, errors), do: errors
  defp validate_json_param("", _field, errors), do: errors

  defp validate_json_param(value, field, errors) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, _} -> errors
      {:error, _} -> ["#{field}: Invalid JSON format" | errors]
    end
  end

  defp validate_json_param(_, _field, errors), do: errors

  defp validate_cost_param(nil, _field, errors), do: errors
  defp validate_cost_param("", _field, errors), do: errors

  defp validate_cost_param(value, field, errors) when is_binary(value) do
    case Float.parse(value) do
      {cost, ""} when cost >= 0 -> errors
      _ -> ["#{field}: Must be a positive number" | errors]
    end
  end

  defp validate_cost_param(value, field, errors) when is_number(value) do
    if value >= 0 do
      errors
    else
      ["#{field}: Must be a positive number" | errors]
    end
  end

  defp validate_cost_param(_, field, errors), do: ["#{field}: Invalid cost value" | errors]

  # Build comprehensive error map from validation error list with detailed messages
  defp build_error_map(validation_errors) when is_list(validation_errors) do
    validation_errors
    |> Enum.reduce(%{}, fn error, acc ->
      case String.split(error, ":", parts: 2) do
        [field, message] ->
          field_atom = String.to_atom(String.trim(field))
          enhanced_message = enhance_field_error_message(field_atom, String.trim(message))
          Map.put(acc, field_atom, enhanced_message)

        [message] ->
          Map.put(acc, :general, String.trim(message))
      end
    end)
  end

  # Enhance field-specific error messages with helpful guidance
  defp enhance_field_error_message(field, message) do
    case field do
      :name ->
        "#{message}. Use a descriptive name like 'OpenAI GPT-4' or 'Local Ollama'."

      :type ->
        "#{message}. Choose from available provider types: openai_compatible, openai, fake."

      :base_url ->
        "#{message}. Examples: https://api.openai.com/v1, http://localhost:1234/v1"

      :auth_type ->
        "#{message}. Select the authentication method supported by your provider."

      :api_key ->
        "#{message}. Enter your provider's API key without extra spaces or quotes."

      :request_timeout_ms ->
        "#{message}. Recommended: 30000ms (30 seconds) for cloud providers, 10000ms for local."

      :connection_timeout_ms ->
        "#{message}. Recommended: 5000ms (5 seconds) for most providers."

      :read_timeout_ms ->
        "#{message}. Should be equal to or greater than request timeout."

      :retries ->
        "#{message}. Recommended: 3 retries for cloud providers, 1 for local."

      :retry_backoff_ms ->
        "#{message}. Recommended: 1000ms (1 second) between retry attempts."

      :requests_per_minute ->
        "#{message}. Check your provider's rate limits. Common values: 60-3000 RPM."

      :requests_per_hour ->
        "#{message}. Should be higher than requests per minute × 60."

      :concurrent_connections ->
        "#{message}. Recommended: 1-10 for most providers to avoid rate limiting."

      :daily_quota ->
        "#{message}. Set based on your provider's daily limits."

      :monthly_quota ->
        "#{message}. Set based on your provider's monthly limits."

      :input_token_cost_per_1k ->
        "#{message}. Enter cost per 1000 input tokens (e.g., 0.001 for $0.001)."

      :output_token_cost_per_1k ->
        "#{message}. Enter cost per 1000 output tokens (usually higher than input)."

      :request_cost ->
        "#{message}. Enter cost per API request for request-based billing."

      :monthly_subscription ->
        "#{message}. Enter monthly subscription cost if applicable."

      :default_headers ->
        "#{message}. Must be valid JSON object, e.g., {\"User-Agent\": \"MyApp/1.0\"}"

      :custom_params ->
        "#{message}. Must be valid JSON object for additional parameters."

      :oauth2_config ->
        "#{message}. Must include client_id, client_secret, and token_url fields."

      :custom_auth_headers ->
        "#{message}. Must be valid JSON object with header names and values."

      _ ->
        message
    end
  end

  # Security helper functions

  defp has_authentication_config?(provider_params) do
    auth_type = Map.get(provider_params, "auth_type")

    case auth_type do
      "none" ->
        false

      nil ->
        false

      "" ->
        false

      _ ->
        # Check if any authentication fields are present
        has_api_key = Map.get(provider_params, "api_key") not in [nil, ""]
        has_oauth2 = Map.get(provider_params, "oauth2_config") not in [nil, ""]
        has_custom_headers = Map.get(provider_params, "custom_auth_headers") not in [nil, ""]

        has_api_key || has_oauth2 || has_custom_headers
    end
  end

  # Build user-friendly success messages
  defp build_success_message(action, name \\ nil)

  defp build_success_message("created", name) when is_binary(name) do
    "Provider '#{name}' has been created successfully! You can now configure and test the connection."
  end

  defp build_success_message("updated", name) when is_binary(name) do
    "Provider '#{name}' has been updated successfully! Changes are now active."
  end

  defp build_success_message("deleted", name) when is_binary(name) do
    "Provider '#{name}' has been permanently deleted."
  end

  defp build_success_message("enabled", name) when is_binary(name) do
    "Provider '#{name}' is now enabled and available for use."
  end

  defp build_success_message("disabled", name) when is_binary(name) do
    "Provider '#{name}' has been disabled and is no longer available for use."
  end

  defp build_success_message(action, _name) do
    "Operation '#{action}' completed successfully."
  end

  # Build comprehensive user-friendly error messages with troubleshooting hints
  defp build_error_message(operation, reason, name \\ nil)

  defp build_error_message("save", reason, name) when is_binary(name) do
    base_message = "Failed to save provider '#{name}': #{reason}"
    troubleshooting = get_save_troubleshooting_hints(reason)
    "#{base_message}. #{troubleshooting}"
  end

  defp build_error_message("delete", reason, name) when is_binary(name) do
    base_message = "Failed to delete provider '#{name}': #{reason}"
    troubleshooting = get_delete_troubleshooting_hints(reason)
    "#{base_message}. #{troubleshooting}"
  end

  defp build_error_message("toggle status", reason, name) when is_binary(name) do
    base_message = "Failed to change status of provider '#{name}': #{reason}"
    troubleshooting = get_status_troubleshooting_hints(reason)
    "#{base_message}. #{troubleshooting}"
  end

  defp build_error_message("connection_test", reason, name) when is_binary(name) do
    base_message = "Connection test failed for provider '#{name}': #{reason}"
    troubleshooting = get_connection_troubleshooting_hints(reason)
    "#{base_message}. #{troubleshooting}"
  end

  defp build_error_message("authentication_test", reason, name) when is_binary(name) do
    base_message = "Authentication test failed for provider '#{name}': #{reason}"
    troubleshooting = get_auth_troubleshooting_hints(reason)
    "#{base_message}. #{troubleshooting}"
  end

  defp build_error_message("validation", reason, _name) do
    base_message = "Validation failed: #{reason}"
    troubleshooting = get_validation_troubleshooting_hints(reason)
    "#{base_message}. #{troubleshooting}"
  end

  defp build_error_message("load providers", reason, _name) do
    base_message = "Failed to load providers: #{reason}"
    troubleshooting = get_load_troubleshooting_hints(reason)
    "#{base_message}. #{troubleshooting}"
  end

  defp build_error_message(operation, reason, _name) do
    base_message = "Failed to #{operation}: #{reason}"
    troubleshooting = get_generic_troubleshooting_hints(operation, reason)
    "#{base_message}. #{troubleshooting}"
  end

  # Detailed troubleshooting hints for different error scenarios
  defp get_save_troubleshooting_hints(reason) do
    cond do
      String.contains?(reason, "name") ->
        "Please ensure the provider name is unique and contains only valid characters."

      String.contains?(reason, "url") or String.contains?(reason, "URL") ->
        "Please check that the base URL is valid and accessible. Example: https://api.openai.com/v1"

      String.contains?(reason, "auth") or String.contains?(reason, "credential") ->
        "Please verify your authentication credentials are correct and properly formatted."

      String.contains?(reason, "timeout") ->
        "Please check your timeout values are reasonable (1-300000 milliseconds)."

      String.contains?(reason, "rate") or String.contains?(reason, "limit") ->
        "Please ensure rate limit values are positive integers within reasonable ranges."

      String.contains?(reason, "json") or String.contains?(reason, "JSON") ->
        "Please check that JSON fields contain valid JSON syntax."

      true ->
        "Please review all form fields for errors and try again."
    end
  end

  defp get_delete_troubleshooting_hints(reason) do
    cond do
      String.contains?(reason, "in use") or String.contains?(reason, "referenced") ->
        "This provider may be actively used by profiles or agents. Disable it first or check dependencies."

      String.contains?(reason, "not found") ->
        "The provider may have already been deleted. Please refresh the page."

      String.contains?(reason, "permission") or String.contains?(reason, "access") ->
        "You may not have permission to delete this provider. Contact your administrator."

      true ->
        "Please try refreshing the page or contact support if the problem persists."
    end
  end

  defp get_status_troubleshooting_hints(reason) do
    cond do
      String.contains?(reason, "not found") ->
        "The provider may have been deleted. Please refresh the page."

      String.contains?(reason, "validation") ->
        "The provider configuration may be incomplete. Please edit and complete all required fields."

      true ->
        "Please try again or refresh the page if the problem persists."
    end
  end

  defp get_connection_troubleshooting_hints(reason) do
    cond do
      String.contains?(reason, "timeout") ->
        "Check your network connection and increase timeout values if needed. Verify the provider's service status."

      String.contains?(reason, "dns") or String.contains?(reason, "resolve") ->
        "Check the base URL spelling and ensure the domain is accessible from your network."

      String.contains?(reason, "ssl") or String.contains?(reason, "certificate") ->
        "There may be SSL/TLS certificate issues. Verify the provider uses HTTPS and has valid certificates."

      String.contains?(reason, "401") or String.contains?(reason, "unauthorized") ->
        "Authentication failed. Please check your API key or authentication credentials."

      String.contains?(reason, "403") or String.contains?(reason, "forbidden") ->
        "Access denied. Verify your API key has the necessary permissions."

      String.contains?(reason, "404") or String.contains?(reason, "not found") ->
        "The API endpoint was not found. Check the base URL and API version."

      String.contains?(reason, "429") or String.contains?(reason, "rate limit") ->
        "Rate limit exceeded. Wait a moment and try again, or adjust your rate limits."

      String.contains?(reason, "500") or String.contains?(reason, "server error") ->
        "The provider's server is experiencing issues. Try again later."

      true ->
        "Check your network connection, provider configuration, and the provider's service status."
    end
  end

  defp get_auth_troubleshooting_hints(reason) do
    cond do
      String.contains?(reason, "api key") or String.contains?(reason, "key") ->
        "Verify your API key is correct and has not expired. Check for extra spaces or characters."

      String.contains?(reason, "oauth") or String.contains?(reason, "OAuth") ->
        "Check your OAuth2 configuration including client ID, secret, and token URLs."

      String.contains?(reason, "token") ->
        "Your authentication token may have expired. Try refreshing or regenerating it."

      String.contains?(reason, "header") ->
        "Check your custom authentication headers are properly formatted."

      true ->
        "Verify all authentication credentials are correct and properly configured."
    end
  end

  defp get_validation_troubleshooting_hints(reason) do
    cond do
      String.contains?(reason, "required") ->
        "Please fill in all required fields marked with an asterisk (*)."

      String.contains?(reason, "format") ->
        "Please check the format of your input values (URLs, numbers, JSON, etc.)."

      String.contains?(reason, "range") ->
        "Please ensure numeric values are within the acceptable ranges."

      true ->
        "Please review the highlighted fields and correct any validation errors."
    end
  end

  defp get_load_troubleshooting_hints(reason) do
    cond do
      String.contains?(reason, "database") or String.contains?(reason, "connection") ->
        "There may be a database connectivity issue. Please try refreshing the page."

      String.contains?(reason, "timeout") ->
        "The request timed out. Please try again or contact support if this persists."

      true ->
        "Please refresh the page or contact support if the problem continues."
    end
  end

  defp get_generic_troubleshooting_hints(operation, reason) do
    cond do
      String.contains?(reason, "network") or String.contains?(reason, "connection") ->
        "Check your network connection and try again."

      String.contains?(reason, "timeout") ->
        "The operation timed out. Please try again."

      String.contains?(reason, "permission") or String.contains?(reason, "access") ->
        "You may not have permission to perform this operation. Contact your administrator."

      true ->
        "Please try again or contact support if the problem persists."
    end
  end

  # Enhance test results with additional context and formatting
  defp enhance_test_result(test_result, provider_name) do
    test_result
    |> Map.put(:provider_name, provider_name)
    |> Map.put(:timestamp, DateTime.utc_now())
    |> Map.update(:troubleshooting_hints, [], fn hints ->
      case test_result.overall_status do
        :success ->
          ["✅ All tests passed successfully!" | hints]

        :warning ->
          ["⚠️ Some tests passed with warnings. Review the details below." | hints]

        :error ->
          [
            "❌ Tests failed. Check the specific error details and follow the troubleshooting steps."
            | hints
          ]

        _ ->
          hints
      end
    end)
    |> add_performance_insights()
  end

  # Add performance insights based on response times
  defp add_performance_insights(test_result) do
    case test_result[:response_time_ms] do
      nil ->
        test_result

      time when time < 1000 ->
        Map.update(
          test_result,
          :performance_notes,
          ["🚀 Excellent response time (#{time}ms)"],
          &["🚀 Excellent response time (#{time}ms)" | &1]
        )

      time when time < 3000 ->
        Map.update(
          test_result,
          :performance_notes,
          ["✅ Good response time (#{time}ms)"],
          &["✅ Good response time (#{time}ms)" | &1]
        )

      time when time < 10000 ->
        Map.update(
          test_result,
          :performance_notes,
          ["⚠️ Slow response time (#{time}ms) - consider optimizing"],
          &["⚠️ Slow response time (#{time}ms) - consider optimizing" | &1]
        )

      time ->
        Map.update(
          test_result,
          :performance_notes,
          ["🐌 Very slow response time (#{time}ms) - check network and provider status"],
          &["🐌 Very slow response time (#{time}ms) - check network and provider status" | &1]
        )
    end
  end

  defp format_test_timestamp(nil), do: "Unknown"

  defp format_test_timestamp(%DateTime{} = dt) do
    dt
    |> DateTime.to_string()
    |> String.replace("T", " ")
    |> String.replace("Z", " UTC")
  end

  defp format_test_timestamp(timestamp) when is_binary(timestamp), do: timestamp

  defp test_multiple_providers_async(providers) do
    # Test providers concurrently with a reasonable timeout
    tasks =
      Enum.map(providers, fn provider ->
        Task.async(fn ->
          {provider.id, Providers.test_provider_connection(provider.id)}
        end)
      end)

    # Wait for all tasks to complete with timeout
    # 30 second timeout
    Task.await_many(tasks, 30_000)
  rescue
    _ ->
      # If any task fails, return empty results
      []
  end

  defp get_empty_provider do
    %{
      id: nil,
      name: "",
      enabled: true,
      type: :openai_compatible,  # Use registry-based default type
      description: "",
      # Endpoint configuration
      base_url: "",
      api_version: "",
      request_timeout_ms: 30000,
      connection_timeout_ms: 5000,
      read_timeout_ms: 30000,
      retries: 3,
      retry_backoff_ms: 1000,
      default_headers: nil,
      custom_params: nil,
      # Authentication
      auth_type: :api_key,
      api_key: "",
      oauth2_config: nil,
      custom_auth_headers: nil,
      token_refresh_url: "",
      credentials_encrypted: false,
      # Rate limiting
      requests_per_minute: nil,
      requests_per_hour: nil,
      concurrent_connections: nil,
      daily_quota: nil,
      monthly_quota: nil,
      burst_limit: nil,
      # Cost configuration
      input_token_cost_per_1k: nil,
      output_token_cost_per_1k: nil,
      request_cost: nil,
      monthly_subscription: nil,
      currency: "USD",
      billing_model: :token_based,
      # Health status
      health_status: :unknown,
      last_check_at: nil,
      response_time_ms: nil,
      error_rate: nil,
      uptime_percentage: nil,
      last_error: nil,
      consecutive_failures: 0,
      # Metadata
      tags: [],
      supported_models: []
    }
  end

  # Provider type management and validation helpers

  defp convert_string_to_provider_type(type_string) when is_binary(type_string) do
    # Convert string to atom, ensuring it's a valid provider type
    try do
      type_atom = String.to_existing_atom(type_string)

      # Verify it's registered in the provider registry
      case AgentRuntime.Providers.Registry.get_provider(type_atom) do
        {:ok, _module} -> type_atom
        {:error, :not_found} -> :openai_compatible  # Default fallback
      end
    rescue
      ArgumentError ->
        # If atom doesn't exist, fallback to default
        :openai_compatible
    end
  end

  defp convert_string_to_provider_type(type_atom) when is_atom(type_atom), do: type_atom

  defp get_type_specific_fields(provider_type) do
    case provider_type do
      :openai_compatible ->
        %{
          required_fields: [:base_url, :auth_type],
          recommended_fields: [:api_version, :api_key],
          hidden_fields: [],
          default_values: %{
            request_timeout_ms: 30_000,
            connection_timeout_ms: 5_000,
            retries: 3,
            auth_type: :api_key,
            api_version: "v1"
          }
        }

      :openai ->
        %{
          required_fields: [:base_url, :auth_type, :api_key],
          recommended_fields: [:api_version],
          hidden_fields: [],
          default_values: %{
            base_url: "https://api.openai.com/v1",
            request_timeout_ms: 30_000,
            connection_timeout_ms: 5_000,
            retries: 3,
            auth_type: :api_key,
            api_version: "v1"
          }
        }

      :fake ->
        %{
          required_fields: [],
          recommended_fields: [],
          hidden_fields: [:api_key, :oauth2_config, :custom_auth_headers, :monthly_subscription, :currency],
          default_values: %{
            base_url: "http://localhost:8080/fake",
            request_timeout_ms: 1_000,
            connection_timeout_ms: 500,
            retries: 0,
            auth_type: :none,
            billing_model: :request_based
          }
        }

      _ ->
        # Default fallback for unknown types
        %{
          required_fields: [:base_url],
          recommended_fields: [:auth_type],
          hidden_fields: [],
          default_values: %{
            request_timeout_ms: 30_000,
            connection_timeout_ms: 5_000,
            retries: 3,
            auth_type: :api_key
          }
        }
    end
  end

  defp validate_provider_type_requirements(provider_params, provider_type) do
    type_config = get_type_specific_fields(provider_type)
    errors = []

    # Check required fields for this provider type
    errors =
      Enum.reduce(type_config.required_fields, errors, fn field, acc ->
        field_value = Map.get(provider_params, to_string(field))

        if is_nil(field_value) or (is_binary(field_value) and String.trim(field_value) == "") do
          ["#{field}: Required for #{provider_type} providers" | acc]
        else
          acc
        end
      end)

    # Registry-based validation - no hardcoded type-specific validation
    # All provider types from the registry are valid
    if Enum.empty?(errors) do
      :ok
    else
      {:error, errors}
    end
  end

  defp should_show_field?(field_name, provider_type) do
    type_config = get_type_specific_fields(provider_type)
    !Enum.member?(type_config.hidden_fields, field_name)
  end

  defp get_available_provider_type_options do
    case AgentRuntime.Providers.Registry.list_providers() do
      {:ok, providers} ->
        providers
        |> Enum.map(fn {name, _module} ->
          %{
            value: to_string(name),
            label: format_provider_type_label(name)
          }
        end)
        |> Enum.sort_by(& &1.label)

      {:error, _} ->
        # Fallback options if registry is unavailable
        [
          %{value: "openai_compatible", label: "OpenAI Compatible"},
          %{value: "fake", label: "Fake Provider"}
        ]
    end
  end

  defp format_provider_type_label(type_atom) do
    type_atom
    |> to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp get_top_provider_type_stats(by_type_map) do
    by_type_map
    |> Enum.to_list()
    |> Enum.sort_by(fn {_type, count} -> count end, :desc)
    |> Enum.take(3)  # Show top 3 provider types
  end

  defp get_type_color(type) do
    case type do
      :openai_compatible -> "info"
      :openai -> "info"
      :fake -> "secondary"
      _ -> "neutral"
    end
  end

  defp is_field_required?(field_name, provider_type) do
    type_config = get_type_specific_fields(provider_type)
    Enum.member?(type_config.required_fields, field_name)
  end

  defp is_field_recommended?(field_name, provider_type) do
    type_config = get_type_specific_fields(provider_type)
    Enum.member?(type_config.recommended_fields, field_name)
  end

  defp get_field_css_classes(field_name, provider_type, base_classes, error_classes \\ nil) do
    classes = [base_classes]

    classes =
      if is_field_required?(field_name, provider_type) do
        ["border-l-4 border-l-primary" | classes]
      else
        classes
      end

    classes =
      if is_field_recommended?(field_name, provider_type) do
        ["border-l-2 border-l-secondary" | classes]
      else
        classes
      end

    classes =
      if error_classes do
        [error_classes | classes]
      else
        classes
      end

    Enum.join(List.flatten(classes), " ")
  end

  defp get_base_url_placeholder(provider_type) do
    case provider_type do
      :openai_compatible -> "https://api.openai.com/v1"
      :openai -> "https://api.openai.com/v1"
      :fake -> "http://localhost:8080/fake"
      :anthropic -> "https://api.anthropic.com"
      :azure_openai -> "https://your-resource.openai.azure.com"
      :google -> "https://generativelanguage.googleapis.com/v1"
      :cohere -> "https://api.cohere.ai/v1"
      :huggingface -> "https://api-inference.huggingface.co/models"
      _ -> "https://api.example.com"
    end
  end

  # Enhanced flash message component with better styling, auto-dismiss, progress indicators, and accessibility
  attr :flash, :map, required: true
  attr :last_operation, :string, default: nil
  attr :operation_status, :atom, default: nil

  defp enhanced_flash(assigns) do
    ~H"""
    <!-- Success Flash with Auto-dismiss and Progress Bar -->
    <div
      :if={Phoenix.Flash.get(@flash, :info)}
      class="alert alert-success shadow-lg mb-4 animate-in slide-in-from-top-2 duration-300 relative overflow-hidden"
      id="success-flash"
      phx-hook="AutoDismissFlash"
      data-dismiss-delay="5000"
      role="alert"
      aria-live="polite"
    >
      <!-- Progress bar for auto-dismiss -->
      <div class="absolute bottom-0 left-0 h-1 bg-success-content/20 w-full">
        <div class="h-full bg-success-content/60 animate-progress-bar" style="animation-duration: 5s;">
        </div>
      </div>

      <div class="flex items-center gap-3">
        <.icon name="hero-check-circle" class="size-6 text-success flex-shrink-0 animate-bounce-once" />
        <div class="flex-1 min-w-0">
          <div class="font-medium flex items-center gap-2">
            Success!
            <div :if={@operation_status == :success} class="badge badge-success badge-xs">
              {String.capitalize(@last_operation || "completed")}
            </div>
          </div>

          <div class="text-sm opacity-90 break-words">{Phoenix.Flash.get(@flash, :info)}</div>

          <div :if={@last_operation} class="text-xs opacity-70 mt-1 flex items-center gap-1">
            <.icon name="hero-clock" class="size-3" />
            Operation: {String.capitalize(@last_operation || "unknown")} completed successfully
          </div>
        </div>

        <button
          class="btn btn-ghost btn-sm hover:bg-success-focus focus:bg-success-focus transition-colors"
          onclick="this.parentElement.parentElement.style.display='none'"
          aria-label="Dismiss success message"
          title="Dismiss (or wait 5 seconds)"
        >
          <.icon name="hero-x-mark" class="size-4" />
        </button>
      </div>
    </div>
    <!-- Error Flash (no auto-dismiss for errors) with Enhanced Styling -->
    <div
      :if={Phoenix.Flash.get(@flash, :error)}
      class="alert alert-error shadow-lg mb-4 animate-in slide-in-from-top-2 duration-300 border-l-4 border-l-error"
      id="error-flash"
      role="alert"
      aria-live="assertive"
    >
      <div class="flex items-center gap-3">
        <.icon name="hero-exclamation-triangle" class="size-6 text-error flex-shrink-0 animate-pulse" />
        <div class="flex-1 min-w-0">
          <div class="font-medium flex items-center gap-2">
            Error Occurred
            <div :if={@operation_status == :error} class="badge badge-error badge-xs">
              {String.capitalize(@last_operation || "failed")}
            </div>
          </div>

          <div class="text-sm opacity-90 break-words leading-relaxed">
            {Phoenix.Flash.get(@flash, :error)}
          </div>

          <div :if={@last_operation} class="text-xs opacity-70 mt-2 flex items-center gap-1">
            <.icon name="hero-exclamation-circle" class="size-3" />
            Failed operation: {String.capitalize(@last_operation || "unknown")}
          </div>
          <!-- Quick action buttons for common error scenarios -->
          <div class="flex gap-2 mt-3">
            <button
              class="btn btn-error btn-xs"
              onclick="window.location.reload()"
              title="Refresh the page"
            >
              <.icon name="hero-arrow-path" class="size-3 mr-1" /> Refresh Page
            </button>
            <button
              class="btn btn-ghost btn-xs"
              onclick="navigator.clipboard.writeText(this.closest('.alert').querySelector('.break-words').textContent)"
              title="Copy error message"
            >
              <.icon name="hero-clipboard" class="size-3 mr-1" /> Copy Error
            </button>
          </div>
        </div>

        <button
          class="btn btn-ghost btn-sm hover:bg-error-focus focus:bg-error-focus transition-colors"
          onclick="this.parentElement.parentElement.style.display='none'"
          aria-label="Dismiss error message"
          title="Dismiss error message"
        >
          <.icon name="hero-x-mark" class="size-4" />
        </button>
      </div>
    </div>
    <!-- Warning Flash with Auto-dismiss and Enhanced Styling -->
    <div
      :if={Phoenix.Flash.get(@flash, :warning)}
      class="alert alert-warning shadow-lg mb-4 animate-in slide-in-from-top-2 duration-300 relative overflow-hidden border-l-4 border-l-warning"
      id="warning-flash"
      phx-hook="AutoDismissFlash"
      data-dismiss-delay="7000"
      role="alert"
      aria-live="polite"
    >
      <!-- Progress bar for auto-dismiss -->
      <div class="absolute bottom-0 left-0 h-1 bg-warning-content/20 w-full">
        <div class="h-full bg-warning-content/60 animate-progress-bar" style="animation-duration: 7s;">
        </div>
      </div>

      <div class="flex items-center gap-3">
        <.icon
          name="hero-exclamation-triangle"
          class="size-6 text-warning flex-shrink-0 animate-pulse"
        />
        <div class="flex-1 min-w-0">
          <div class="font-medium flex items-center gap-2">
            Warning
            <div :if={@operation_status == :warning} class="badge badge-warning badge-xs">
              {String.capitalize(@last_operation || "completed")}
            </div>
          </div>

          <div class="text-sm opacity-90 break-words leading-relaxed">
            {Phoenix.Flash.get(@flash, :warning)}
          </div>

          <div :if={@last_operation} class="text-xs opacity-70 mt-1 flex items-center gap-1">
            <.icon name="hero-information-circle" class="size-3" />
            Operation: {String.capitalize(@last_operation || "unknown")} completed with warnings
          </div>
        </div>

        <button
          class="btn btn-ghost btn-sm hover:bg-warning-focus focus:bg-warning-focus transition-colors"
          onclick="this.parentElement.parentElement.style.display='none'"
          aria-label="Dismiss warning message"
          title="Dismiss (or wait 7 seconds)"
        >
          <.icon name="hero-x-mark" class="size-4" />
        </button>
      </div>
    </div>
    """
  end

  # Components
  attr :providers, :list, required: true
  attr :search_query, :string, required: true
  attr :type_filter, :string, required: true
  attr :status_filter, :string, required: true
  attr :enabled_filter, :string, required: true
  attr :provider_stats, :map, required: true
  attr :loading, :boolean, default: false
  attr :deleting, :boolean, default: false
  attr :testing_connection, :boolean, default: false
  attr :performing_health_check, :boolean, default: false
  attr :group_by_type, :boolean, default: false

  defp providers_list(assigns) do
    # Χρησιμοποιήστε safe get για όλα τα missing attributes
    assigns =
      assigns
      |> assign_new(:testing_all_connections, fn -> false end)
      |> assign_new(:testing_authentication, fn -> false end)
      |> assign_new(:group_by_type, fn -> false end)

    ~H"""
    <div class="flex flex-col h-full space-y-4">
      <!-- Loading Overlay for List -->
      <div
        :if={@loading}
        class="absolute inset-0 bg-base-100/50 backdrop-blur-sm flex items-center justify-center z-50 rounded-lg"
      >
        <div class="flex flex-col items-center gap-4">
          <span class="loading loading-spinner loading-lg text-primary"></span>
          <p class="text-base-content/70 font-medium">Loading providers...</p>
        </div>
      </div>
      <!-- Provider Statistics -->
      <div class="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-6 gap-2">
        <.stat_card title="Total" value={@provider_stats.total} color="primary" />
        <.stat_card title="Enabled" value={@provider_stats.enabled} color="success" />
        <.stat_card title="Disabled" value={@provider_stats.disabled} color="warning" />
        <%= for {type, count} <- get_top_provider_type_stats(@provider_stats.by_type) do %>
          <.stat_card
            title={format_provider_type_label(type)}
            value={count}
            color={get_type_color(type)}
          />
        <% end %>
      </div>
      <!-- Enhanced Filters and Search -->
      <div class="sticky top-0 z-10 bg-base-100 pt-2 pb-4 space-y-4 border-b">
        <!-- Primary Search Bar -->
        <div class="flex flex-wrap gap-3 items-center">
          <div class="form-control flex-1 min-w-[200px]">
            <div class="relative">
              <input
                type="text"
                placeholder="Search providers by name, description, or URL..."
                class="input input-bordered input-sm w-full pl-10"
                value={@search_query}
                phx-change="search_providers"
                phx-value-search={@search_query}
                phx-debounce="300"
              />
              <.icon
                name="hero-magnifying-glass"
                class="absolute left-3 top-1/2 transform -translate-y-1/2 size-4 text-base-content/50"
              />
            </div>
          </div>
          <!-- Clear Filters Button -->
          <button
            :if={
              @search_query != "" or @type_filter != "all" or @status_filter != "all" or
                @enabled_filter != "all"
            }
            class="btn btn-ghost btn-sm"
            phx-click="clear_filters"
            title="Clear all filters"
          >
            <.icon name="hero-x-mark" class="size-4 mr-1" /> Clear
          </button>
          <!-- Group Toggle -->
          <button
            class={["btn btn-sm", (@group_by_type && "btn-primary") || "btn-outline"]}
            phx-click="toggle_grouping"
            title={if @group_by_type, do: "Disable grouping", else: "Group by type"}
          >
            <.icon name="hero-squares-2x2" class="size-4 mr-1" /> {if @group_by_type,
              do: "Grouped",
              else: "Group"}
          </button>
        </div>
        <!-- Advanced Filters Row -->
        <div class="flex flex-wrap gap-3 items-center">
          <div class="form-control">
            <label class="label label-text text-xs">Type</label>
            <select
              class="select select-bordered select-sm w-40"
              phx-change="filter_by_type"
            >
              <option value="all" selected={@type_filter == "all"}>All Types</option>
              <%= for provider_type <- get_available_provider_type_options() do %>
                <option value={provider_type.value} selected={@type_filter == provider_type.value}>
                  {provider_type.label}
                </option>
              <% end %>
            </select>
          </div>

          <div class="form-control">
            <label class="label label-text text-xs">Health Status</label>
            <select
              class="select select-bordered select-sm w-32"
              phx-change="filter_by_status"
            >
              <option value="all" selected={@status_filter == "all"}>All Status</option>

              <option value="online" selected={@status_filter == "online"}>Online</option>

              <option value="offline" selected={@status_filter == "offline"}>Offline</option>

              <option value="degraded" selected={@status_filter == "degraded"}>Degraded</option>

              <option value="unknown" selected={@status_filter == "unknown"}>Unknown</option>
            </select>
          </div>

          <div class="form-control">
            <label class="label label-text text-xs">Enabled</label>
            <select
              class="select select-bordered select-sm w-32"
              phx-change="filter_by_enabled"
            >
              <option value="all" selected={@enabled_filter == "all"}>All</option>

              <option value="enabled" selected={@enabled_filter == "enabled"}>Enabled</option>

              <option value="disabled" selected={@enabled_filter == "disabled"}>Disabled</option>
            </select>
          </div>
          <!-- Filter Summary -->
          <div class="flex-1 text-sm text-base-content/70">
            Showing {length(@providers)} of {@provider_stats.total} providers
            <%= if @search_query != "" or @type_filter != "all" or @status_filter != "all" or @enabled_filter != "all" do %>
              (filtered)
            <% end %>
          </div>
        </div>
      </div>
      <!-- Providers Display -->
      <div class="flex-1 overflow-hidden min-h-0">
        <%= if @group_by_type do %>
          <.grouped_providers_display
            providers={@providers}
            loading={@loading}
            deleting={@deleting}
            testing_connection={@testing_connection}
            performing_health_check={@performing_health_check}
            testing_all_connections={@testing_all_connections}
            testing_authentication={@testing_authentication}
          />
        <% else %>
          <.flat_providers_display
            providers={@providers}
            loading={@loading}
            deleting={@deleting}
            testing_connection={@testing_connection}
            performing_health_check={@performing_health_check}
            testing_all_connections={@testing_all_connections}
            testing_authentication={@testing_authentication}
          />
        <% end %>
      </div>
    </div>
    """
  end

  # Provider detail component with enhanced connection test results display
  attr :provider, :map, required: true
  attr :connection_test_result, :map, default: nil
  attr :testing_connection, :any, default: false
  attr :performing_health_check, :boolean, default: false

  defp provider_detail(assigns) do
    ~H"""
    <div class="space-y-6 h-full overflow-auto">
      <!-- Provider Information Card -->
      <div class="card bg-base-100 shadow-sm">
        <div class="card-body">
          <div class="flex items-start justify-between mb-4">
            <div class="flex items-center gap-4">
              <div class="avatar placeholder">
                <div class="bg-primary text-primary-content rounded-full w-16">
                  <span class="text-xl font-bold">{String.first(@provider.name)}</span>
                </div>
              </div>

              <div>
                <h2 class="text-xl font-bold">{@provider.name}</h2>

                <p class="text-base-content/70">
                  {@provider.description || "No description provided"}
                </p>

                <div class="flex gap-2 mt-2">
                  <.type_badge type={@provider.type} /> <.status_badge enabled={@provider.enabled} />
                  <.health_badge health_status={@provider.health_status} />
                </div>
              </div>
            </div>

            <div class="flex gap-2">
              <button
                class="btn btn-outline btn-sm"
                phx-click="edit_provider"
                phx-value-provider_id={@provider.id}
              >
                <.icon name="hero-pencil" class="size-4 mr-2" /> Edit
              </button>
            </div>
          </div>
          <!-- Provider Configuration Summary -->
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            <div class="stat bg-base-200 rounded-lg">
              <div class="stat-title">Base URL</div>

              <div class="stat-value text-sm font-mono break-all">
                {@provider.base_url || "Not configured"}
              </div>
            </div>

            <div class="stat bg-base-200 rounded-lg">
              <div class="stat-title">Authentication</div>

              <div class="stat-value text-sm">{format_auth_type(@provider.auth_type)}</div>
            </div>

            <div class="stat bg-base-200 rounded-lg">
              <div class="stat-title">Rate Limits</div>

              <div class="stat-value text-sm">{@provider.rate_limit_summary || "Not configured"}</div>
            </div>
          </div>
        </div>
      </div>
      <!-- Connection Testing Section -->
      <div class="card bg-base-100 shadow-sm">
        <div class="card-body">
          <div class="flex items-center justify-between mb-4">
            <h3 class="text-lg font-semibold flex items-center gap-2">
              <.icon name="hero-signal" class="size-5 text-primary" /> Connection Testing
            </h3>

            <div class="flex gap-2">
              <button
                class={[
                  "btn btn-info btn-sm",
                  @testing_connection && "loading"
                ]}
                phx-click="test_connection"
                phx-value-provider_id={@provider.id}
                disabled={@testing_connection}
              >
                <.icon :if={!@testing_connection} name="hero-signal" class="size-4 mr-2" />
                <span :if={@testing_connection} class="loading loading-spinner loading-sm mr-2">
                </span> {if @testing_connection, do: "Testing...", else: "Test Connection"}
              </button>
              <button
                class={[
                  "btn btn-secondary btn-sm",
                  @testing_connection && "loading"
                ]}
                phx-click="test_authentication"
                phx-value-provider_id={@provider.id}
                disabled={@testing_connection || @provider.auth_type == :none}
              >
                <.icon name="hero-shield-check" class="size-4 mr-2" /> Test Authentication
              </button>
            </div>
          </div>
          <!-- Connection Test Results -->
          <div
            :if={@connection_test_result}
            id="connection-test-results"
            phx-hook="ConnectionTestDisplay"
          >
            <.connection_test_results test_result={@connection_test_result} />
          </div>
          <!-- No Test Results Message -->
          <div :if={!@connection_test_result} class="text-center py-8 text-base-content/60">
            <.icon name="hero-signal-slash" class="size-12 mx-auto mb-4 opacity-50" />
            <p>No connection test results available</p>

            <p class="text-sm">Click "Test Connection" to verify provider connectivity</p>
          </div>
        </div>
      </div>
      <!-- Health Monitoring Section -->
      <div class="card bg-base-100 shadow-sm">
        <div class="card-body">
          <div class="flex items-center justify-between mb-4">
            <h3 class="text-lg font-semibold flex items-center gap-2">
              <.icon name="hero-heart" class="size-5 text-primary" /> Health Monitoring
            </h3>

            <button
              class={[
                "btn btn-success btn-sm",
                @performing_health_check && "loading"
              ]}
              phx-click="perform_health_check"
              phx-value-provider_id={@provider.id}
              disabled={@performing_health_check}
            >
              <.icon :if={!@performing_health_check} name="hero-heart" class="size-4 mr-2" />
              <span :if={@performing_health_check} class="loading loading-spinner loading-sm mr-2">
              </span> {if @performing_health_check, do: "Checking...", else: "Check Health"}
            </button>
          </div>

          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
            <div class="stat bg-base-200 rounded-lg">
              <div class="stat-title">Status</div>

              <div class="stat-value text-sm">
                <.health_badge health_status={@provider.health_status} />
              </div>
            </div>

            <div class="stat bg-base-200 rounded-lg">
              <div class="stat-title">Response Time</div>

              <div class="stat-value text-sm">
                {if @provider.response_time_ms, do: "#{@provider.response_time_ms}ms", else: "Unknown"}
              </div>
            </div>

            <div class="stat bg-base-200 rounded-lg">
              <div class="stat-title">Error Rate</div>

              <div class="stat-value text-sm">
                {if @provider.error_rate,
                  do: "#{Float.round(@provider.error_rate, 2)}%",
                  else: "Unknown"}
              </div>
            </div>

            <div class="stat bg-base-200 rounded-lg">
              <div class="stat-title">Uptime</div>

              <div class="stat-value text-sm">
                {if @provider.uptime_percentage,
                  do: "#{Float.round(@provider.uptime_percentage, 1)}%",
                  else: "Unknown"}
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Connection test results component with detailed troubleshooting
  attr :test_result, :map, required: true

  defp connection_test_results(assigns) do
    ~H"""
    <div class="space-y-4">
      <!-- Overall Status -->
      <div class={[
        "alert",
        case @test_result.overall_status do
          :success -> "alert-success"
          :warning -> "alert-warning"
          :error -> "alert-error"
          _ -> "alert-info"
        end
      ]}>
        <div class="flex items-center gap-3">
          <.icon
            name={
              case @test_result.overall_status do
                :success -> "hero-check-circle"
                :warning -> "hero-exclamation-triangle"
                :error -> "hero-x-circle"
                _ -> "hero-information-circle"
              end
            }
            class="size-6 flex-shrink-0"
          />
          <div class="flex-1">
            <div class="font-medium">
              Connection Test {String.capitalize(to_string(@test_result.overall_status))}
            </div>

            <div class="text-sm opacity-90">
              Provider: {@test_result.provider_name || "Unknown"} •
              Tested: {format_test_timestamp(@test_result.timestamp)} •
              Response Time: {if @test_result.response_time_ms,
                do: "#{@test_result.response_time_ms}ms",
                else: "N/A"}
            </div>
          </div>
        </div>
      </div>
      <!-- Performance Insights -->
      <div :if={@test_result[:performance_notes]} class="card bg-base-200 shadow-sm">
        <div class="card-body p-4">
          <h4 class="font-medium text-sm mb-2 flex items-center gap-2">
            <.icon name="hero-chart-bar" class="size-4" /> Performance Insights
          </h4>

          <ul class="space-y-1">
            <li :for={note <- @test_result.performance_notes} class="text-sm flex items-center gap-2">
              <span class="w-2 h-2 bg-current rounded-full opacity-50"></span> {note}
            </li>
          </ul>
        </div>
      </div>
      <!-- Detailed Test Results -->
      <div
        :if={@test_result.tests && map_size(@test_result.tests) > 0}
        class="grid grid-cols-1 md:grid-cols-2 gap-4"
      >
        <div
          :for={{test_name, test_details} <- @test_result.tests}
          class="test-result-card card bg-base-200 shadow-sm"
        >
          <div class="card-body p-4">
            <div class="flex items-center justify-between mb-2">
              <h4 class="font-medium text-sm">
                {String.capitalize(String.replace(to_string(test_name), "_", " "))}
              </h4>

              <div class={[
                "badge badge-sm",
                case test_details.status do
                  :success -> "badge-success"
                  :warning -> "badge-warning"
                  :error -> "badge-error"
                  _ -> "badge-ghost"
                end
              ]}>
                {String.capitalize(to_string(test_details.status))}
              </div>
            </div>

            <p class="text-xs text-base-content/70">{test_details.details}</p>

            <div :if={test_details.response_time_ms} class="text-xs text-base-content/60 mt-1">
              Response: {test_details.response_time_ms}ms
            </div>
          </div>
        </div>
      </div>
      <!-- Error Details -->
      <div
        :if={@test_result.error_details && length(@test_result.error_details) > 0}
        class="card bg-error/10 border border-error/20 shadow-sm"
      >
        <div class="card-body p-4">
          <h4 class="font-medium text-sm mb-3 text-error flex items-center gap-2">
            <.icon name="hero-exclamation-triangle" class="size-4" /> Error Details
          </h4>

          <ul class="space-y-2">
            <li
              :for={error <- @test_result.error_details}
              class="text-sm text-error bg-error/5 p-2 rounded border-l-2 border-error"
            >
              {error}
            </li>
          </ul>
        </div>
      </div>
      <!-- Troubleshooting Hints -->
      <div
        :if={@test_result.troubleshooting_hints && length(@test_result.troubleshooting_hints) > 0}
        class="card bg-info/10 border border-info/20 shadow-sm"
      >
        <div class="card-body p-4">
          <h4 class="font-medium text-sm mb-3 text-info flex items-center gap-2">
            <.icon name="hero-light-bulb" class="size-4" /> Troubleshooting Hints
          </h4>

          <ul class="space-y-2">
            <li
              :for={hint <- @test_result.troubleshooting_hints}
              class="text-sm flex items-start gap-2"
            >
              <.icon name="hero-arrow-right" class="size-3 mt-0.5 text-info flex-shrink-0" />
              <span>{hint}</span>
            </li>
          </ul>
        </div>
      </div>
      <!-- Quick Actions -->
      <div class="flex flex-wrap gap-2 pt-2">
        <button
          class="btn btn-outline btn-xs"
          onclick="navigator.clipboard.writeText(JSON.stringify(this.closest('[phx-hook]').dataset, null, 2))"
        >
          <.icon name="hero-clipboard" class="size-3 mr-1" /> Copy Results
        </button>
        <button
          class="btn btn-outline btn-xs"
          phx-click="test_connection"
          phx-value-provider_id={@test_result[:provider_id]}
        >
          <.icon name="hero-arrow-path" class="size-3 mr-1" /> Retest
        </button>
      </div>
    </div>
    """
  end

  # Flat providers display component
  attr :providers, :list, required: true
  attr :loading, :boolean, default: false
  attr :deleting, :boolean, default: false
  attr :testing_connection, :boolean, default: false
  attr :performing_health_check, :boolean, default: false
  attr :testing_all_connections, :boolean, default: false
  attr :testing_authentication, :boolean, default: false

  defp flat_providers_display(assigns) do
    ~H"""
    <div class="card bg-base-200 shadow-sm h-full">
      <div class="card-body p-0 h-full">
        <div class="overflow-auto h-full">
          <table class="table table-sm table-pin-rows">
            <thead>
              <tr class="sticky top-0 bg-base-200 z-10">
                <th>Provider</th>

                <th>Type</th>

                <th>Status</th>

                <th>Health</th>

                <th>Authentication</th>

                <th>Rate Limits</th>

                <th class="w-32">Actions</th>
              </tr>
            </thead>

            <tbody>
              <tr :for={provider <- @providers} class="hover">
                <td>
                  <div class="flex items-center gap-3">
                    <div class="avatar placeholder">
                      <div class="bg-neutral text-neutral-content rounded-full w-8">
                        <span class="text-xs">{String.first(provider.name)}</span>
                      </div>
                    </div>

                    <div>
                      <div class="font-medium">{provider.name}</div>

                      <div class="text-sm text-base-content/70">
                        {provider.description || "No description"}
                      </div>

                      <%= if provider.base_url do %>
                        <div class="text-xs text-base-content/50 font-mono">{provider.base_url}</div>
                      <% end %>
                    </div>
                  </div>
                </td>

                <td><.type_badge type={provider.type} /></td>

                <td><.status_badge enabled={provider.enabled} /></td>

                <td><.health_badge health_status={provider.health_status} /></td>

                <td class="text-sm">{format_auth_type(provider.auth_type)}</td>

                <td class="text-sm">{provider.rate_limit_summary}</td>

                <td>
                  <.provider_actions
                    provider={provider}
                    deleting={@deleting}
                    testing_connection={@testing_connection}
                    performing_health_check={@performing_health_check}
                    testing_all_connections={@testing_all_connections}
                    testing_authentication={@testing_authentication}
                  />
                </td>
              </tr>
              <!-- Empty state -->
              <tr :if={Enum.empty?(@providers)}>
                <td colspan="7" class="text-center py-8">
                  <div class="flex flex-col items-center justify-center">
                    <.icon name="hero-server-stack" class="size-12 text-base-content/30 mb-4" />
                    <p class="text-base-content/70">No providers found</p>

                    <p class="text-sm text-base-content/50">
                      Try adjusting your search or filters, or create a new provider
                    </p>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  # Provider actions component with enhanced loading states and progress indicators
  attr :provider, :map, required: true
  attr :deleting, :boolean, default: false
  # Can be boolean or provider_id
  attr :testing_connection, :any, default: false
  attr :performing_health_check, :boolean, default: false
  attr :testing_all_connections, :boolean, default: false
  # Can be boolean or provider_id
  attr :testing_authentication, :any, default: false

  defp provider_actions(assigns) do
    # Determine if this specific provider is being tested
    assigns =
      assign(
        assigns,
        :is_testing_connection,
        assigns.testing_connection == assigns.provider.id || assigns.testing_all_connections
      )

    assigns =
      assign(assigns, :is_testing_auth, assigns.testing_authentication == assigns.provider.id)

    ~H"""
    <div class="flex gap-1">
      <button
        class="btn btn-ghost btn-xs tooltip"
        phx-click="view_provider"
        phx-value-provider_id={@provider.id}
        data-tip="View Provider Details"
      >
        <.icon name="hero-eye" class="size-3" />
      </button>
      <button
        class="btn btn-ghost btn-xs tooltip"
        phx-click="edit_provider"
        phx-value-provider_id={@provider.id}
        data-tip="Edit Provider Configuration"
      >
        <.icon name="hero-pencil" class="size-3" />
      </button>
      <button
        class={[
          "btn btn-xs tooltip",
          if(@provider.enabled, do: "btn-warning", else: "btn-success")
        ]}
        phx-click="toggle_status"
        phx-value-provider_id={@provider.id}
        data-tip={if @provider.enabled, do: "Disable Provider", else: "Enable Provider"}
      >
        <.icon
          name={if @provider.enabled, do: "hero-pause", else: "hero-play"}
          class="size-3"
        />
      </button>
      <button
        class={[
          "btn btn-success btn-xs tooltip",
          @performing_health_check && "loading"
        ]}
        phx-click="perform_health_check"
        phx-value-provider_id={@provider.id}
        data-tip="Perform Health Check"
        disabled={@performing_health_check}
      >
        <.icon :if={!@performing_health_check} name="hero-heart" class="size-3" />
        <span :if={@performing_health_check} class="loading loading-spinner loading-xs"></span>
      </button>
      <button
        class={[
          "btn btn-info btn-xs tooltip",
          @is_testing_connection && "loading"
        ]}
        phx-click="test_connection"
        phx-value-provider_id={@provider.id}
        data-tip={
          if @is_testing_connection,
            do: "Testing Connection...",
            else: "Test Connection"
        }
        disabled={@is_testing_connection}
      >
        <.icon :if={!@is_testing_connection} name="hero-signal" class="size-3" />
        <span :if={@is_testing_connection} class="loading loading-spinner loading-xs"></span>
      </button>
      <button
        class={[
          "btn btn-secondary btn-xs tooltip",
          @is_testing_auth && "loading"
        ]}
        phx-click="test_authentication"
        phx-value-provider_id={@provider.id}
        data-tip={
          cond do
            @provider.auth_type == :none -> "No Authentication Configured"
            @is_testing_auth -> "Testing Authentication..."
            true -> "Test Authentication"
          end
        }
        disabled={@is_testing_auth || @provider.auth_type == :none}
      >
        <.icon :if={!@is_testing_auth} name="hero-shield-check" class="size-3" />
        <span :if={@is_testing_auth} class="loading loading-spinner loading-xs"></span>
      </button>
      <button
        class="btn btn-ghost btn-xs tooltip"
        phx-click="view_health_metrics"
        phx-value-provider_id={@provider.id}
        data-tip="View Detailed Health Metrics"
      >
        <.icon name="hero-chart-bar" class="size-3" />
      </button>
      <button
        class={[
          "btn btn-error btn-xs tooltip",
          @deleting && "loading"
        ]}
        phx-click="delete_provider"
        phx-value-provider_id={@provider.id}
        onclick={"return confirm('⚠️ Delete Provider\\n\\nAre you sure you want to permanently delete \"#{@provider.name}\"?\\n\\nThis action cannot be undone and may affect any profiles or agents using this provider.')"}
        data-tip={
          if @deleting,
            do: "Deleting Provider...",
            else: "Delete Provider"
        }
        disabled={@deleting}
      >
        <.icon :if={!@deleting} name="hero-trash" class="size-3" />
        <span :if={@deleting} class="loading loading-spinner loading-xs"></span>
      </button>
    </div>
    """
  end

  # Helper function for type descriptions
  defp get_type_description(type) do
    case type do
      :openai_compatible -> "OpenAI API compatible providers"
      :openai -> "Official OpenAI API provider"
      :fake -> "Fake provider for testing and development"
      _ -> "AI service providers"
    end
  end

  # Helper function to format authentication types
  defp format_auth_type(auth_type) do
    case auth_type do
      :api_key -> "API Key"
      :oauth2 -> "OAuth2"
      :custom_header -> "Custom Header"
      :none -> "None"
      nil -> "Not configured"
      _ -> String.capitalize(to_string(auth_type))
    end
  end

  # Grouped providers display component
  attr :providers, :list, required: true
  attr :loading, :boolean, default: false
  attr :deleting, :boolean, default: false
  attr :testing_connection, :boolean, default: false
  attr :performing_health_check, :boolean, default: false
  attr :testing_all_connections, :boolean, default: false
  attr :testing_authentication, :boolean, default: false

  defp grouped_providers_display(assigns) do
    # Group providers by type
    grouped_providers = Enum.group_by(assigns.providers, & &1.type)
    assigns = assign(assigns, :grouped_providers, grouped_providers)

    ~H"""
    <div class="space-y-6 h-full overflow-auto">
      <%= for {type, providers} <- @grouped_providers do %>
        <div class="card bg-base-200 shadow-sm">
          <div class="card-body p-4">
            <div class="flex items-center justify-between mb-4">
              <div class="flex items-center gap-3">
                <.type_badge type={type} />
                <h3 class="text-lg font-semibold capitalize">{to_string(type)} Providers</h3>

                <div class="badge badge-neutral">{length(providers)}</div>
              </div>

              <div class="text-sm text-base-content/70">{get_type_description(type)}</div>
            </div>

            <div class="overflow-x-auto">
              <table class="table table-sm">
                <thead>
                  <tr>
                    <th>Provider</th>

                    <th>Status</th>

                    <th>Health</th>

                    <th>Authentication</th>

                    <th>Rate Limits</th>

                    <th class="w-32">Actions</th>
                  </tr>
                </thead>

                <tbody>
                  <tr :for={provider <- providers} class="hover">
                    <td>
                      <div class="flex items-center gap-3">
                        <div class="avatar placeholder">
                          <div class="bg-neutral text-neutral-content rounded-full w-8">
                            <span class="text-xs">{String.first(provider.name)}</span>
                          </div>
                        </div>

                        <div>
                          <div class="font-medium">{provider.name}</div>

                          <div class="text-sm text-base-content/70">
                            {provider.description || "No description"}
                          </div>

                          <%= if provider.base_url do %>
                            <div class="text-xs text-base-content/50 font-mono">
                              {provider.base_url}
                            </div>
                          <% end %>
                        </div>
                      </div>
                    </td>

                    <td><.status_badge enabled={provider.enabled} /></td>

                    <td><.health_badge health_status={provider.health_status} /></td>

                    <td class="text-sm">{format_auth_type(provider.auth_type)}</td>

                    <td class="text-sm">{provider.rate_limit_summary}</td>

                    <td>
                      <.provider_actions
                        provider={provider}
                        deleting={@deleting}
                        testing_connection={@testing_connection}
                        performing_health_check={@performing_health_check}
                        testing_all_connections={@testing_all_connections}
                        testing_authentication={@testing_authentication}
                      />
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </div>
      <% end %>
      <!-- Empty state for grouped view -->
      <div :if={Enum.empty?(@providers)} class="card bg-base-200 shadow-sm">
        <div class="card-body text-center py-12">
          <.icon name="hero-server-stack" class="size-16 text-base-content/30 mb-4 mx-auto" />
          <h3 class="text-lg font-semibold mb-2">No providers found</h3>

          <p class="text-base-content/70 mb-4">
            Try adjusting your search or filters, or create a new provider
          </p>
        </div>
      </div>
    </div>
    """
  end

  # Missing component functions

  # Stat card component
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

  # Type badge component
  attr :type, :atom, required: true

  defp type_badge(assigns) do
    {badge_class, icon} =
      case assigns.type do
        :openai_compatible -> {"badge-info", "hero-cpu-chip"}
        :openai -> {"badge-info", "hero-sparkles"}
        :fake -> {"badge-secondary", "hero-beaker"}
        _ -> {"badge-ghost", "hero-question-mark-circle"}
      end

    assigns = assign(assigns, :badge_class, badge_class)
    assigns = assign(assigns, :icon, icon)

    ~H"""
    <div class={["badge badge-sm gap-1", @badge_class]}>
      <.icon name={@icon} class="size-3" /> {format_provider_type_label(@type)}
    </div>
    """
  end

  # Status badge component
  attr :enabled, :boolean, required: true

  defp status_badge(assigns) do
    {badge_class, icon, text} =
      if assigns.enabled do
        {"badge-success", "hero-check-circle", "Enabled"}
      else
        {"badge-error", "hero-x-circle", "Disabled"}
      end

    assigns = assign(assigns, :badge_class, badge_class)
    assigns = assign(assigns, :icon, icon)
    assigns = assign(assigns, :text, text)

    ~H"""
    <div class={["badge badge-sm gap-1", @badge_class]}>
      <.icon name={@icon} class="size-3" /> {@text}
    </div>
    """
  end

  # Health badge component
  attr :health_status, :atom, required: true

  defp health_badge(assigns) do
    {badge_class, icon, text} =
      case assigns.health_status do
        :online -> {"badge-success", "hero-heart", "Online"}
        :offline -> {"badge-error", "hero-x-circle", "Offline"}
        :degraded -> {"badge-warning", "hero-exclamation-triangle", "Degraded"}
        :unknown -> {"badge-ghost", "hero-question-mark-circle", "Unknown"}
        _ -> {"badge-ghost", "hero-question-mark-circle", "Unknown"}
      end

    assigns = assign(assigns, :badge_class, badge_class)
    assigns = assign(assigns, :icon, icon)
    assigns = assign(assigns, :text, text)

    ~H"""
    <div class={["badge badge-sm gap-1", @badge_class]}>
      <.icon name={@icon} class="size-3" /> {@text}
    </div>
    """
  end

  # Comprehensive provider form with enhanced validation and user experience
  attr :provider, :map, required: true
  attr :mode, :atom, required: true
  attr :available_provider_types, :list, required: true
  attr :available_auth_types, :list, required: true
  attr :saving, :boolean, default: false
  attr :form_errors, :map, default: %{}
  attr :validation_errors, :map, default: %{}

  defp provider_form(assigns) do
    ~H"""
    <div class="card bg-base-200 shadow-sm" id="provider-form" phx-hook="RealTimeValidation">
      <!-- Loading Overlay for Form -->
      <div
        :if={@saving}
        class="absolute inset-0 bg-base-100/50 backdrop-blur-sm flex items-center justify-center z-50 rounded-lg"
      >
        <div class="flex flex-col items-center gap-4">
          <span class="loading loading-spinner loading-lg text-primary"></span>
          <p class="text-base-content/70 font-medium">
            {if @mode == :create, do: "Creating provider...", else: "Updating provider..."}
          </p>
        </div>
      </div>

      <div class="card-body">
        <div class="flex items-center justify-between mb-6">
          <div>
            <h3 class="text-lg font-semibold">
              {if @mode == :create, do: "Create New Provider", else: "Edit Provider"}
            </h3>

            <p class="text-base-content/70 text-sm mt-1">
              {if @mode == :create,
                do: "Configure a new AI service provider for your system",
                else: "Update the configuration for this provider"}
            </p>
          </div>

          <div class="flex gap-2">
            <div class="badge badge-info badge-sm">
              {format_provider_type_label(@provider.type || :openai_compatible)} Provider
            </div>
          </div>
        </div>
        <!-- General Error Display -->
        <div
          :if={@form_errors[:general] || @validation_errors[:general]}
          class="alert alert-error mb-6"
        >
          <.icon name="hero-exclamation-triangle" class="size-5" />
          <div>
            <div class="font-medium">Configuration Error</div>

            <div class="text-sm">{@form_errors[:general] || @validation_errors[:general]}</div>
          </div>
        </div>

        <form phx-submit="save_provider" phx-change="validate_provider" class="space-y-6">
          <!-- Basic Information Section -->
          <div class="card bg-base-100 shadow-sm">
            <div class="card-body p-4">
              <h4 class="font-medium text-base mb-4 flex items-center gap-2">
                <.icon name="hero-information-circle" class="size-5 text-primary" /> Basic Information
              </h4>

              <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                <!-- Provider Name -->
                <div class="form-control">
                  <label class="label">
                    <span class="label-text font-medium">
                      Provider Name <span class="text-error">*</span>
                    </span>
                  </label>
                  <input
                    type="text"
                    name="provider[name]"
                    value={@provider.name}
                    class={[
                      "input input-bordered",
                      @form_errors[:name] && "input-error"
                    ]}
                    placeholder="e.g., OpenAI GPT-4, Local Ollama"
                    required
                  />
                  <div :if={@form_errors[:name]} class="validation-error">
                    <.icon name="hero-exclamation-circle" class="size-4" /> {@form_errors[:name]}
                  </div>
                </div>
                <!-- Provider Type -->
                <div class="form-control">
                  <label class="label">
                    <span class="label-text font-medium">
                      Provider Type <span class="text-error">*</span>
                    </span>
                  </label>
                  <select
                    name="provider[type]"
                    class={[
                      "select select-bordered",
                      @form_errors[:type] && "select-error"
                    ]}
                    phx-change="provider_type_changed"
                    required
                  >
                    <option value="">Select provider type...</option>

                    <option
                      :for={type <- @available_provider_types}
                      value={type.value}
                      selected={to_string(@provider.type) == type.value}
                    >
                      {type.label} - {type.description}
                    </option>
                  </select>
                  <div :if={@form_errors[:type]} class="validation-error">
                    <.icon name="hero-exclamation-circle" class="size-4" /> {@form_errors[:type]}
                  </div>
                </div>
                <!-- Description -->
                <div class="form-control md:col-span-2">
                  <label class="label"><span class="label-text font-medium">Description</span></label> <textarea
                    name="provider[description]"
                    class="textarea textarea-bordered"
                    placeholder="Brief description of this provider and its intended use..."
                    rows="2"
                  >{@provider.description}</textarea>
                </div>
              </div>
            </div>
          </div>
          <!-- Connection Configuration Section -->
          <div class="card bg-base-100 shadow-sm">
            <div class="card-body p-4">
              <h4 class="font-medium text-base mb-4 flex items-center gap-2">
                <.icon name="hero-globe-alt" class="size-5 text-primary" /> Connection Configuration
              </h4>

              <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                <!-- Base URL -->
                <div class="form-control md:col-span-2">
                  <label class="label">
                    <span class="label-text font-medium">
                      Base URL <span class="text-error">*</span>
                    </span>
                  </label>
                  <input
                    type="url"
                    name="provider[base_url]"
                    value={@provider.base_url}
                    class={[
                      "input input-bordered",
                      @form_errors[:base_url] && "input-error"
                    ]}
                    placeholder={get_base_url_placeholder(@provider.type)}
                    required
                  />
                  <div :if={@form_errors[:base_url]} class="validation-error">
                    <.icon name="hero-exclamation-circle" class="size-4" /> {@form_errors[:base_url]}
                  </div>
                </div>
                <!-- API Version -->
                <div class="form-control">
                  <label class="label"><span class="label-text font-medium">API Version</span></label>
                  <input
                    type="text"
                    name="provider[api_version]"
                    value={@provider.api_version}
                    class="input input-bordered"
                    placeholder="v1, 2023-12-01, etc."
                  />
                </div>
                <!-- Request Timeout -->
                <div class="form-control">
                  <label class="label">
                    <span class="label-text font-medium">Request Timeout (ms)</span>
                  </label>
                  <input
                    type="number"
                    name="provider[request_timeout_ms]"
                    value={@provider.request_timeout_ms}
                    class={[
                      "input input-bordered",
                      @form_errors[:request_timeout_ms] && "input-error"
                    ]}
                    placeholder="30000"
                    min="1000"
                    max="300000"
                  />
                  <div :if={@form_errors[:request_timeout_ms]} class="validation-error">
                    <.icon name="hero-exclamation-circle" class="size-4" /> {@form_errors[
                      :request_timeout_ms
                    ]}
                  </div>
                </div>
                <!-- Connection Timeout -->
                <div class="form-control">
                  <label class="label">
                    <span class="label-text font-medium">Connection Timeout (ms)</span>
                  </label>
                  <input
                    type="number"
                    name="provider[connection_timeout_ms]"
                    value={@provider.connection_timeout_ms}
                    class={[
                      "input input-bordered",
                      @form_errors[:connection_timeout_ms] && "input-error"
                    ]}
                    placeholder="5000"
                    min="1000"
                    max="60000"
                  />
                  <div :if={@form_errors[:connection_timeout_ms]} class="validation-error">
                    <.icon name="hero-exclamation-circle" class="size-4" /> {@form_errors[
                      :connection_timeout_ms
                    ]}
                  </div>
                </div>
                <!-- Retries -->
                <div class="form-control">
                  <label class="label"><span class="label-text font-medium">Max Retries</span></label>
                  <input
                    type="number"
                    name="provider[retries]"
                    value={@provider.retries}
                    class={[
                      "input input-bordered",
                      @form_errors[:retries] && "input-error"
                    ]}
                    placeholder="3"
                    min="0"
                    max="10"
                  />
                  <div :if={@form_errors[:retries]} class="validation-error">
                    <.icon name="hero-exclamation-circle" class="size-4" /> {@form_errors[:retries]}
                  </div>
                </div>
              </div>
            </div>
          </div>
          <!-- Authentication Section -->
          <div class="card bg-base-100 shadow-sm">
            <div class="card-body p-4">
              <h4 class="font-medium text-base mb-4 flex items-center gap-2">
                <.icon name="hero-shield-check" class="size-5 text-primary" />
                Authentication Configuration
              </h4>

              <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                <!-- Authentication Type -->
                <div class="form-control">
                  <label class="label">
                    <span class="label-text font-medium">Authentication Type</span>
                  </label>
                  <select
                    name="provider[auth_type]"
                    class="select select-bordered"
                    phx-change="validate_authentication"
                  >
                    <option
                      :for={auth_type <- @available_auth_types}
                      value={auth_type.value}
                      selected={to_string(@provider.auth_type) == auth_type.value}
                    >
                      {auth_type.label}
                    </option>
                  </select>
                </div>
                <!-- API Key (shown when auth_type is api_key) -->
                <div
                  :if={@provider.auth_type == :api_key}
                  class="form-control"
                >
                  <label class="label">
                    <span class="label-text font-medium">
                      API Key <span class="text-error">*</span>
                    </span>
                  </label>
                  <input
                    type="password"
                    name="provider[api_key]"
                    value={@provider.api_key}
                    class={[
                      "input input-bordered",
                      @form_errors[:api_key] && "input-error"
                    ]}
                    placeholder="Enter your API key..."
                  />
                  <div :if={@form_errors[:api_key]} class="validation-error">
                    <.icon name="hero-exclamation-circle" class="size-4" /> {@form_errors[:api_key]}
                  </div>
                </div>
              </div>
            </div>
          </div>
          <!-- Rate Limiting Section -->
          <div class="card bg-base-100 shadow-sm">
            <div class="card-body p-4">
              <h4 class="font-medium text-base mb-4 flex items-center gap-2">
                <.icon name="hero-clock" class="size-5 text-primary" /> Rate Limiting & Quotas
              </h4>

              <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
                <!-- Requests per Minute -->
                <div class="form-control">
                  <label class="label">
                    <span class="label-text font-medium">Requests per Minute</span>
                  </label>
                  <input
                    type="number"
                    name="provider[requests_per_minute]"
                    value={@provider.requests_per_minute}
                    class={[
                      "input input-bordered",
                      @form_errors[:requests_per_minute] && "input-error"
                    ]}
                    placeholder="60"
                    min="1"
                  />
                  <div :if={@form_errors[:requests_per_minute]} class="validation-error">
                    <.icon name="hero-exclamation-circle" class="size-4" /> {@form_errors[
                      :requests_per_minute
                    ]}
                  </div>
                </div>
                <!-- Requests per Hour -->
                <div class="form-control">
                  <label class="label">
                    <span class="label-text font-medium">Requests per Hour</span>
                  </label>
                  <input
                    type="number"
                    name="provider[requests_per_hour]"
                    value={@provider.requests_per_hour}
                    class={[
                      "input input-bordered",
                      @form_errors[:requests_per_hour] && "input-error"
                    ]}
                    placeholder="3600"
                    min="1"
                  />
                  <div :if={@form_errors[:requests_per_hour]} class="validation-error">
                    <.icon name="hero-exclamation-circle" class="size-4" /> {@form_errors[
                      :requests_per_hour
                    ]}
                  </div>
                </div>
                <!-- Concurrent Connections -->
                <div class="form-control">
                  <label class="label">
                    <span class="label-text font-medium">Concurrent Connections</span>
                  </label>
                  <input
                    type="number"
                    name="provider[concurrent_connections]"
                    value={@provider.concurrent_connections}
                    class={[
                      "input input-bordered",
                      @form_errors[:concurrent_connections] && "input-error"
                    ]}
                    placeholder="5"
                    min="1"
                  />
                  <div :if={@form_errors[:concurrent_connections]} class="validation-error">
                    <.icon name="hero-exclamation-circle" class="size-4" /> {@form_errors[
                      :concurrent_connections
                    ]}
                  </div>
                </div>
              </div>
            </div>
          </div>
          <!-- Cost Configuration Section -->
          <div class="card bg-base-100 shadow-sm">
            <div class="card-body p-4">
              <h4 class="font-medium text-base mb-4 flex items-center gap-2">
                <.icon name="hero-currency-dollar" class="size-5 text-primary" /> Cost Configuration
              </h4>

              <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                <!-- Input Token Cost -->
                <div class="form-control">
                  <label class="label">
                    <span class="label-text font-medium">Input Token Cost (per 1K)</span>
                  </label>
                  <input
                    type="number"
                    step="0.000001"
                    name="provider[input_token_cost_per_1k]"
                    value={@provider.input_token_cost_per_1k}
                    class={[
                      "input input-bordered",
                      @form_errors[:input_token_cost_per_1k] && "input-error"
                    ]}
                    placeholder="0.001"
                    min="0"
                  />
                  <div :if={@form_errors[:input_token_cost_per_1k]} class="validation-error">
                    <.icon name="hero-exclamation-circle" class="size-4" /> {@form_errors[
                      :input_token_cost_per_1k
                    ]}
                  </div>
                </div>
                <!-- Output Token Cost -->
                <div class="form-control">
                  <label class="label">
                    <span class="label-text font-medium">Output Token Cost (per 1K)</span>
                  </label>
                  <input
                    type="number"
                    step="0.000001"
                    name="provider[output_token_cost_per_1k]"
                    value={@provider.output_token_cost_per_1k}
                    class={[
                      "input input-bordered",
                      @form_errors[:output_token_cost_per_1k] && "input-error"
                    ]}
                    placeholder="0.002"
                    min="0"
                  />
                  <div :if={@form_errors[:output_token_cost_per_1k]} class="validation-error">
                    <.icon name="hero-exclamation-circle" class="size-4" /> {@form_errors[
                      :output_token_cost_per_1k
                    ]}
                  </div>
                </div>
                <!-- Monthly Subscription -->
                <div class="form-control">
                  <label class="label">
                    <span class="label-text font-medium">Monthly Subscription</span>
                  </label>
                  <input
                    type="number"
                    step="0.01"
                    name="provider[monthly_subscription]"
                    value={@provider.monthly_subscription}
                    class={[
                      "input input-bordered",
                      @form_errors[:monthly_subscription] && "input-error"
                    ]}
                    placeholder="20.00"
                    min="0"
                  />
                  <div :if={@form_errors[:monthly_subscription]} class="validation-error">
                    <.icon name="hero-exclamation-circle" class="size-4" /> {@form_errors[
                      :monthly_subscription
                    ]}
                  </div>
                </div>
                <!-- Currency -->
                <div class="form-control">
                  <label class="label"><span class="label-text font-medium">Currency</span></label>
                  <select
                    name="provider[currency]"
                    class="select select-bordered"
                  >
                    <option value="USD" selected={@provider.currency == "USD"}>
                      USD - US Dollar
                    </option>

                    <option value="EUR" selected={@provider.currency == "EUR"}>EUR - Euro</option>

                    <option value="GBP" selected={@provider.currency == "GBP"}>
                      GBP - British Pound
                    </option>

                    <option value="JPY" selected={@provider.currency == "JPY"}>
                      JPY - Japanese Yen
                    </option>
                  </select>
                </div>
              </div>
            </div>
          </div>
          <!-- Form Actions -->
          <div class="flex flex-col sm:flex-row gap-3 pt-4 border-t">
            <button
              type="submit"
              class={[
                "btn btn-primary flex-1 sm:flex-none",
                @saving && "loading"
              ]}
              disabled={@saving}
              id="provider-form-shortcuts"
              phx-hook="ProviderFormKeyboardShortcuts"
            >
              <.icon :if={!@saving} name="hero-check" class="size-4 mr-2" />
              <span :if={@saving} class="loading loading-spinner loading-sm mr-2"></span> {if @saving,
                do: if(@mode == :create, do: "Creating...", else: "Updating..."),
                else: if(@mode == :create, do: "Create Provider", else: "Update Provider")}
            </button>
            <button
              type="button"
              class="btn btn-outline"
              phx-click="back_to_list"
              disabled={@saving}
            >
              <.icon name="hero-arrow-left" class="size-4 mr-2" /> Cancel
            </button>
            <!-- Test Connection Button (only for edit mode) -->
            <button
              :if={@mode == :edit}
              type="button"
              class="btn btn-info"
              phx-click="test_connection"
              phx-value-provider_id={@provider.id}
              disabled={@saving}
            >
              <.icon name="hero-signal" class="size-4 mr-2" /> Test Connection
            </button>
          </div>
          <!-- Keyboard Shortcuts Help -->
          <div class="text-xs text-base-content/60 mt-4 flex flex-wrap gap-4">
            <span><kbd class="kbd kbd-xs">Ctrl+S</kbd> Save</span>
            <span><kbd class="kbd kbd-xs">Esc</kbd> Cancel</span>
            <span :if={@mode == :edit}><kbd class="kbd kbd-xs">Ctrl+T</kbd> Test Connection</span>
          </div>
        </form>
      </div>
    </div>
    """
  end

  # Health metrics detail component (placeholder)
  attr :metrics, :map, required: true
  attr :loading, :boolean, default: false

  defp health_metrics_detail(assigns) do
    ~H"""
    <div class="card bg-base-200 shadow-sm">
      <div class="card-body">
        <h3 class="text-lg font-semibold mb-4">Health Metrics Detail</h3>

        <p class="text-base-content/70 mb-6">
          Health metrics detail functionality is being implemented. Please check back later.
        </p>

        <div class="flex gap-2">
          <button class="btn btn-outline" phx-click="back_to_list">
            <.icon name="hero-arrow-left" class="size-4 mr-2" /> Back to List
          </button>
        </div>
      </div>
    </div>
    """
  end

  # Analytics dashboard component (placeholder)
  attr :analytics, :map, required: true
  attr :loading, :boolean, default: false
  attr :view_mode, :atom, default: :overview

  defp analytics_dashboard(assigns) do
    ~H"""
    <div class="card bg-base-200 shadow-sm">
      <div class="card-body">
        <h3 class="text-lg font-semibold mb-4">Analytics Dashboard</h3>

        <p class="text-base-content/70 mb-6">
          Analytics dashboard functionality is being implemented. Please check back later.
        </p>
      </div>
    </div>
    """
  end

  # Health dashboard component (placeholder)
  attr :metrics, :map, required: true
  attr :loading, :boolean, default: false
  attr :performing_bulk_health_check, :boolean, default: false

  defp health_dashboard(assigns) do
    ~H"""
    <div class="card bg-base-200 shadow-sm">
      <div class="card-body">
        <h3 class="text-lg font-semibold mb-4">Health Dashboard</h3>

        <p class="text-base-content/70 mb-6">
          Health dashboard functionality is being implemented. Please check back later.
        </p>
      </div>
    </div>
    """
  end

  # Comprehensive help and documentation component
  attr :show_help, :boolean, default: false

  defp comprehensive_help(assigns) do
    ~H"""
    <div
      :if={@show_help}
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm"
    >
      <div class="modal-box max-w-6xl max-h-[90vh] overflow-y-auto">
        <div class="flex items-center justify-between mb-6">
          <h2 class="text-2xl font-bold">Provider Management Help & Documentation</h2>

          <button class="btn btn-ghost btn-sm" phx-click="toggle_help">
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>

        <div class="tabs tabs-boxed mb-6">
          <a class="tab tab-active" data-tab="overview">Overview</a>
          <a class="tab" data-tab="shortcuts">Shortcuts</a>
          <a class="tab" data-tab="provider-types">Provider Types</a>
          <a class="tab" data-tab="authentication">Authentication</a>
          <a class="tab" data-tab="troubleshooting">Troubleshooting</a>
        </div>
        <!-- Overview Tab -->
        <div class="tab-content" data-tab-content="overview">
          <div class="prose max-w-none">
            <h3>Provider Management System</h3>

            <p>The Provider Management system allows you to configure and manage AI service providers
              that power your applications. This includes cloud services like OpenAI and Anthropic,
              local services like Ollama, and custom implementations.</p>

            <h4>Key Features</h4>

            <ul>
              <li>
                <strong>Provider Configuration:</strong>
                Set up connection details, authentication, and rate limits
              </li>

              <li>
                <strong>Connection Testing:</strong> Verify provider connectivity and authentication
              </li>

              <li>
                <strong>Health Monitoring:</strong>
                Track provider status, response times, and error rates
              </li>

              <li><strong>Cost Management:</strong> Configure and track usage costs</li>

              <li><strong>Security:</strong> Encrypted credential storage and secure logging</li>
            </ul>

            <h4>Getting Started</h4>

            <ol>
              <li>Click "New Provider" to create a provider</li>

              <li>Select the appropriate provider type</li>

              <li>Configure connection settings and authentication</li>

              <li>Test the connection to verify configuration</li>

              <li>Save and enable the provider</li>
            </ol>
          </div>
        </div>
        <!-- Shortcuts Tab -->
        <div class="tab-content hidden" data-tab-content="shortcuts">
          <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div>
              <h4 class="font-semibold mb-3">Global Shortcuts</h4>

              <div class="space-y-2">
                <div class="flex justify-between items-center">
                  <span>Create new provider</span> <kbd class="kbd kbd-sm">Ctrl+N</kbd>
                </div>

                <div class="flex justify-between items-center">
                  <span>Search providers</span> <kbd class="kbd kbd-sm">Ctrl+F</kbd>
                </div>

                <div class="flex justify-between items-center">
                  <span>Refresh list</span> <kbd class="kbd kbd-sm">F5</kbd>
                </div>

                <div class="flex justify-between items-center">
                  <span>Show help</span> <kbd class="kbd kbd-sm">F1</kbd>
                </div>
              </div>
            </div>

            <div>
              <h4 class="font-semibold mb-3">Form Shortcuts</h4>

              <div class="space-y-2">
                <div class="flex justify-between items-center">
                  <span>Save provider</span> <kbd class="kbd kbd-sm">Ctrl+S</kbd>
                </div>

                <div class="flex justify-between items-center">
                  <span>Cancel/Return to list</span> <kbd class="kbd kbd-sm">Esc</kbd>
                </div>

                <div class="flex justify-between items-center">
                  <span>Test connection</span> <kbd class="kbd kbd-sm">Ctrl+T</kbd>
                </div>

                <div class="flex justify-between items-center">
                  <span>Test authentication</span> <kbd class="kbd kbd-sm">Ctrl+Shift+T</kbd>
                </div>
              </div>
            </div>

            <div>
              <h4 class="font-semibold mb-3">Navigation Shortcuts</h4>

              <div class="space-y-2">
                <div class="flex justify-between items-center">
                  <span>Basic Information</span> <kbd class="kbd kbd-sm">Alt+1</kbd>
                </div>

                <div class="flex justify-between items-center">
                  <span>Connection Config</span> <kbd class="kbd kbd-sm">Alt+2</kbd>
                </div>

                <div class="flex justify-between items-center">
                  <span>Authentication</span> <kbd class="kbd kbd-sm">Alt+3</kbd>
                </div>

                <div class="flex justify-between items-center">
                  <span>Rate Limits</span> <kbd class="kbd kbd-sm">Alt+4</kbd>
                </div>

                <div class="flex justify-between items-center">
                  <span>Cost Configuration</span> <kbd class="kbd kbd-sm">Alt+5</kbd>
                </div>
              </div>
            </div>

            <div>
              <h4 class="font-semibold mb-3">Accessibility</h4>

              <div class="space-y-2">
                <div class="flex justify-between items-center">
                  <span>Toggle high contrast</span> <kbd class="kbd kbd-sm">Alt+C</kbd>
                </div>

                <div class="flex justify-between items-center">
                  <span>Toggle reduced motion</span> <kbd class="kbd kbd-sm">Alt+M</kbd>
                </div>

                <div class="flex justify-between items-center">
                  <span>Toggle theme</span> <kbd class="kbd kbd-sm">Alt+T</kbd>
                </div>
              </div>
            </div>
          </div>
        </div>
        <!-- Provider Types Tab -->
        <div class="tab-content hidden" data-tab-content="provider-types">
          <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div class="card bg-base-100 shadow-sm">
              <div class="card-body">
                <h4 class="card-title text-info">
                  <.icon name="hero-cloud" class="size-5" /> Cloud Providers
                </h4>

                <p class="text-sm text-base-content/70 mb-3">
                  External cloud-based AI services hosted by third parties.
                </p>

                <div class="space-y-2 text-sm">
                  <div><strong>Examples:</strong> OpenAI, Anthropic, Google AI, Azure OpenAI</div>

                  <div><strong>Required:</strong> Base URL, Authentication (API Key/OAuth2)</div>

                  <div><strong>Recommended:</strong> Rate limits, cost configuration</div>

                  <div><strong>Base URL Examples:</strong></div>

                  <ul class="list-disc list-inside ml-4 space-y-1 font-mono text-xs">
                    <li>https://api.openai.com/v1</li>

                    <li>https://api.anthropic.com</li>

                    <li>https://generativelanguage.googleapis.com/v1</li>
                  </ul>
                </div>
              </div>
            </div>

            <div class="card bg-base-100 shadow-sm">
              <div class="card-body">
                <h4 class="card-title text-secondary">
                  <.icon name="hero-computer-desktop" class="size-5" /> Local Providers
                </h4>

                <p class="text-sm text-base-content/70 mb-3">
                  Self-hosted AI services running on your infrastructure.
                </p>

                <div class="space-y-2 text-sm">
                  <div><strong>Examples:</strong> Ollama, LocalAI, Text Generation WebUI</div>

                  <div><strong>Required:</strong> Base URL (localhost/private IP)</div>

                  <div><strong>Recommended:</strong> Lower timeouts, no subscription costs</div>

                  <div><strong>Base URL Examples:</strong></div>

                  <ul class="list-disc list-inside ml-4 space-y-1 font-mono text-xs">
                    <li>http://localhost:11434/v1</li>

                    <li>http://192.168.1.100:8080/v1</li>

                    <li>http://10.0.0.50:5000/v1</li>
                  </ul>
                </div>
              </div>
            </div>

            <div class="card bg-base-100 shadow-sm">
              <div class="card-body">
                <h4 class="card-title text-accent">
                  <.icon name="hero-building-office" class="size-5" /> Enterprise Providers
                </h4>

                <p class="text-sm text-base-content/70 mb-3">
                  Corporate or enterprise-grade AI services with enhanced security.
                </p>

                <div class="space-y-2 text-sm">
                  <div><strong>Examples:</strong> Azure OpenAI, AWS Bedrock, Corporate APIs</div>

                  <div><strong>Required:</strong> Base URL, Secure Authentication (OAuth2)</div>

                  <div><strong>Recommended:</strong> Credential encryption, audit logging</div>

                  <div><strong>Security Features:</strong></div>

                  <ul class="list-disc list-inside ml-4 space-y-1 text-xs">
                    <li>Automatic credential encryption</li>

                    <li>Enhanced audit logging</li>

                    <li>Compliance-ready configuration</li>
                  </ul>
                </div>
              </div>
            </div>

            <div class="card bg-base-100 shadow-sm">
              <div class="card-body">
                <h4 class="card-title text-neutral">
                  <.icon name="hero-cog-6-tooth" class="size-5" /> Custom Providers
                </h4>

                <p class="text-sm text-base-content/70 mb-3">
                  Specialized or custom AI service implementations.
                </p>

                <div class="space-y-2 text-sm">
                  <div>
                    <strong>Examples:</strong> Custom APIs, Specialized models, Proxy services
                  </div>

                  <div><strong>Required:</strong> Base URL</div>

                  <div><strong>Flexible:</strong> Custom authentication, parameters</div>

                  <div><strong>Use Cases:</strong></div>

                  <ul class="list-disc list-inside ml-4 space-y-1 text-xs">
                    <li>Custom model endpoints</li>

                    <li>Proxy or gateway services</li>

                    <li>Specialized AI implementations</li>
                  </ul>
                </div>
              </div>
            </div>
          </div>
        </div>
        <!-- Authentication Tab -->
        <div class="tab-content hidden" data-tab-content="authentication">
          <div class="space-y-6">
            <div class="alert alert-info">
              <.icon name="hero-shield-check" class="size-5" />
              <div>
                <h4 class="font-semibold">Security Notice</h4>

                <p class="text-sm">
                  All credentials are automatically encrypted before storage and masked in the UI for security.
                </p>
              </div>
            </div>

            <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div class="card bg-base-100 shadow-sm">
                <div class="card-body">
                  <h4 class="card-title">API Key Authentication</h4>

                  <p class="text-sm text-base-content/70 mb-3">
                    Most common authentication method for AI services.
                  </p>

                  <div class="space-y-2 text-sm">
                    <div><strong>Best for:</strong> OpenAI, Anthropic, most cloud providers</div>

                    <div><strong>Format:</strong> Usually starts with "sk-" or similar prefix</div>

                    <div><strong>Security:</strong> Automatically encrypted and masked</div>

                    <div class="mockup-code text-xs">
                      <pre><code>API Key: sk-proj-abc123...xyz789</code></pre>
                    </div>
                  </div>
                </div>
              </div>

              <div class="card bg-base-100 shadow-sm">
                <div class="card-body">
                  <h4 class="card-title">OAuth2 Authentication</h4>

                  <p class="text-sm text-base-content/70 mb-3">
                    Enterprise-grade authentication with token refresh.
                  </p>

                  <div class="space-y-2 text-sm">
                    <div><strong>Best for:</strong> Enterprise providers, Azure OpenAI</div>

                    <div><strong>Required:</strong> Client ID, Client Secret, Token URL</div>

                    <div><strong>Features:</strong> Automatic token refresh</div>

                    <div class="mockup-code text-xs">
                      <pre phx-no-curly-interpolation><code>{
    "client_id": "your-client-id",
    "client_secret": "your-secret",
    "token_url": "https://login.provider.com/oauth/token"
    }</code></pre>
                    </div>
                  </div>
                </div>
              </div>

              <div class="card bg-base-100 shadow-sm">
                <div class="card-body">
                  <h4 class="card-title">Custom Header Authentication</h4>

                  <p class="text-sm text-base-content/70 mb-3">
                    Flexible authentication using custom HTTP headers.
                  </p>

                  <div class="space-y-2 text-sm">
                    <div><strong>Best for:</strong> Custom APIs, proxy services</div>

                    <div><strong>Format:</strong> JSON object with header names and values</div>

                    <div><strong>Examples:</strong> Bearer tokens, custom API keys</div>

                    <div class="mockup-code text-xs">
                      <pre phx-no-curly-interpolation><code>{
    "Authorization": "Bearer your-token",
    "X-API-Key": "your-api-key"
    }</code></pre>
                    </div>
                  </div>
                </div>
              </div>

              <div class="card bg-base-100 shadow-sm">
                <div class="card-body">
                  <h4 class="card-title">No Authentication</h4>

                  <p class="text-sm text-base-content/70 mb-3">
                    For open or internal services that don't require authentication.
                  </p>

                  <div class="space-y-2 text-sm">
                    <div><strong>Best for:</strong> Local services, internal APIs</div>

                    <div><strong>Security:</strong> Only use for trusted networks</div>

                    <div><strong>Note:</strong> Consider network security measures</div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
        <!-- Troubleshooting Tab -->
        <div class="tab-content hidden" data-tab-content="troubleshooting">
          <div class="space-y-6">
            <div class="alert alert-warning">
              <.icon name="hero-exclamation-triangle" class="size-5" />
              <div>
                <h4 class="font-semibold">Common Issues</h4>

                <p class="text-sm">
                  Most provider issues are related to configuration, authentication, or network connectivity.
                </p>
              </div>
            </div>

            <div class="collapse-group">
              <div class="collapse collapse-arrow bg-base-200">
                <input type="radio" name="troubleshooting-accordion" />
                <div class="collapse-title text-lg font-medium">Connection Test Failures</div>

                <div class="collapse-content">
                  <div class="space-y-3 text-sm">
                    <div>
                      <strong>Timeout Errors:</strong>
                      <ul class="list-disc list-inside ml-4 mt-1">
                        <li>Check network connectivity to the provider</li>

                        <li>Increase timeout values (30s for cloud, 10s for local)</li>

                        <li>Verify the provider's service status</li>
                      </ul>
                    </div>

                    <div>
                      <strong>DNS Resolution Errors:</strong>
                      <ul class="list-disc list-inside ml-4 mt-1">
                        <li>Verify the base URL spelling</li>

                        <li>Check if the domain is accessible from your network</li>

                        <li>Try accessing the URL in a browser</li>
                      </ul>
                    </div>

                    <div>
                      <strong>SSL/TLS Certificate Errors:</strong>
                      <ul class="list-disc list-inside ml-4 mt-1">
                        <li>Ensure the provider uses HTTPS with valid certificates</li>

                        <li>Check if your network has SSL inspection</li>

                        <li>Verify the certificate chain is complete</li>
                      </ul>
                    </div>
                  </div>
                </div>
              </div>

              <div class="collapse collapse-arrow bg-base-200">
                <input type="radio" name="troubleshooting-accordion" />
                <div class="collapse-title text-lg font-medium">Authentication Issues</div>

                <div class="collapse-content">
                  <div class="space-y-3 text-sm">
                    <div>
                      <strong>401 Unauthorized:</strong>
                      <ul class="list-disc list-inside ml-4 mt-1">
                        <li>Verify your API key is correct and hasn't expired</li>

                        <li>Check for extra spaces or characters in credentials</li>

                        <li>Ensure the API key has necessary permissions</li>
                      </ul>
                    </div>

                    <div>
                      <strong>403 Forbidden:</strong>
                      <ul class="list-disc list-inside ml-4 mt-1">
                        <li>Check if your API key has the required permissions</li>

                        <li>Verify your account has access to the specific models</li>

                        <li>Check if there are IP restrictions on your account</li>
                      </ul>
                    </div>

                    <div>
                      <strong>OAuth2 Token Issues:</strong>
                      <ul class="list-disc list-inside ml-4 mt-1">
                        <li>Verify client ID and secret are correct</li>

                        <li>Check the token URL is accessible</li>

                        <li>Ensure the OAuth2 scope includes necessary permissions</li>
                      </ul>
                    </div>
                  </div>
                </div>
              </div>

              <div class="collapse collapse-arrow bg-base-200">
                <input type="radio" name="troubleshooting-accordion" />
                <div class="collapse-title text-lg font-medium">Rate Limiting & Quotas</div>

                <div class="collapse-content">
                  <div class="space-y-3 text-sm">
                    <div>
                      <strong>429 Rate Limited:</strong>
                      <ul class="list-disc list-inside ml-4 mt-1">
                        <li>Reduce requests per minute/hour settings</li>

                        <li>Implement exponential backoff in your application</li>

                        <li>Check your provider's rate limit documentation</li>
                      </ul>
                    </div>

                    <div>
                      <strong>Quota Exceeded:</strong>
                      <ul class="list-disc list-inside ml-4 mt-1">
                        <li>Check your account's usage limits</li>

                        <li>Upgrade your plan if necessary</li>

                        <li>Set appropriate daily/monthly quotas</li>
                      </ul>
                    </div>
                  </div>
                </div>
              </div>

              <div class="collapse collapse-arrow bg-base-200">
                <input type="radio" name="troubleshooting-accordion" />
                <div class="collapse-title text-lg font-medium">Configuration Validation</div>

                <div class="collapse-content">
                  <div class="space-y-3 text-sm">
                    <div>
                      <strong>URL Format Errors:</strong>
                      <ul class="list-disc list-inside ml-4 mt-1">
                        <li>Ensure URLs start with http:// or https://</li>

                        <li>Include the correct API version in the path</li>

                        <li>Don't include trailing slashes unless required</li>
                      </ul>
                    </div>

                    <div>
                      <strong>JSON Configuration Errors:</strong>
                      <ul class="list-disc list-inside ml-4 mt-1">
                        <li>Validate JSON syntax in custom headers/params</li>

                        <li>Use double quotes for JSON strings</li>

                        <li>Ensure proper escaping of special characters</li>
                      </ul>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <div class="card bg-base-100 shadow-sm">
              <div class="card-body">
                <h4 class="card-title">Getting Help</h4>

                <div class="space-y-2 text-sm">
                  <p>If you're still experiencing issues:</p>

                  <ul class="list-disc list-inside ml-4 space-y-1">
                    <li>Use the "Copy Error" button to copy error messages</li>

                    <li>Check the provider's documentation and status page</li>

                    <li>Test the connection using the provider's official tools</li>

                    <li>Contact your system administrator or support team</li>
                  </ul>
                </div>
              </div>
            </div>
          </div>
        </div>

        <div class="modal-action">
          <button class="btn btn-primary" phx-click="toggle_help">Close Help</button>
        </div>
      </div>
    </div>

    <script>
      // Tab switching functionality
      document.addEventListener('click', function(e) {
        if (e.target.classList.contains('tab')) {
          e.preventDefault();

          // Remove active class from all tabs
          document.querySelectorAll('.tab').forEach(tab => {
            tab.classList.remove('tab-active');
          });

          // Add active class to clicked tab
          e.target.classList.add('tab-active');

          // Hide all tab contents
          document.querySelectorAll('.tab-content').forEach(content => {
            content.classList.add('hidden');
          });

          // Show selected tab content
          const targetTab = e.target.getAttribute('data-tab');
          const targetContent = document.querySelector(`[data-tab-content="${targetTab}"]`);
          if (targetContent) {
            targetContent.classList.remove('hidden');
          }
        }
      });
    </script>
    """
  end
end
