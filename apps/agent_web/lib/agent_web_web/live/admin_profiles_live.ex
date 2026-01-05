defmodule AgentWebWeb.AdminProfilesLive do
  @moduledoc """
  Admin profiles management LiveView for LLM profile management.
  Provides interface for LLM profile CRUD operations, model configuration, and performance tracking.
  """
  use AgentWebWeb, :live_view
  require AgentWebWeb.AdminErrorHandler
  alias AgentWebWeb.{AdminLayouts, AdminErrorHandler}
  alias AgentWeb.Llm

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to profile-related events
      Phoenix.PubSub.subscribe(AgentWeb.PubSub, "admin:profiles")
    end

    {:ok,
     socket
     |> assign(:current_page, :profiles)
     |> assign(:current_section, :management)
     |> assign(:sidebar_collapsed, false)
     |> assign(:page_title, "LLM Profiles")
     |> assign(:view_mode, :list)
     |> assign(:selected_profile, nil)
     |> assign(:search_query, "")
     |> assign(:provider_filter, "all")
     |> assign(:status_filter, "all")
     |> assign(:selected_profiles, [])
     |> assign(:show_bulk_actions, false)
     # Enhanced error handling and UX state
     |> assign(:loading, false)
     |> assign(:saving, false)
     |> assign(:deleting, false)
     |> assign(:form_errors, %{})
     |> assign(:validation_errors, %{})
     |> assign(:last_operation, nil)
     |> assign(:operation_status, nil)
     |> load_profiles_data()}
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

  @impl true
  def handle_event("search_profiles", %{"search" => query}, socket) do
    {:noreply,
     socket
     |> assign(:search_query, query)
     |> filter_profiles()}
  end

  @impl true
  def handle_event("filter_by_provider", %{"provider" => provider}, socket) do
    {:noreply,
     socket
     |> assign(:provider_filter, provider)
     |> filter_profiles()}
  end

  @impl true
  def handle_event("filter_by_status", %{"status" => status}, socket) do
    {:noreply,
     socket
     |> assign(:status_filter, status)
     |> filter_profiles()}
  end

  @impl true
  def handle_event("view_profile", %{"profile_id" => profile_id}, socket) do
    profile = Enum.find(socket.assigns.all_profiles, &(&1.id == profile_id))

    {:noreply,
     socket
     |> assign(:selected_profile, profile)
     |> assign(:view_mode, :detail)}
  end

  @impl true
  def handle_event("edit_profile", %{"profile_id" => profile_id}, socket) do
    profile = Enum.find(socket.assigns.all_profiles, &(&1.id == profile_id))

    # Convert UI profile to form-compatible format for proper pre-population
    form_profile = convert_ui_profile_to_form_format(profile)

    {:noreply,
     socket
     |> assign(:selected_profile, form_profile)
     |> assign(:view_mode, :edit)
     |> assign(:form_errors, %{})
     |> assign(:validation_errors, %{})
     |> assign(:saving, false)}
  end

  @impl true
  def handle_event("create_profile", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_profile, get_empty_profile())
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
     |> assign(:selected_profile, nil)
     |> assign(:form_errors, %{})
     |> assign(:validation_errors, %{})
     |> assign(:saving, false)
     |> assign(:deleting, false)}
  end

  @impl true
  def handle_event("validate_profile", %{"profile" => profile_params}, socket) do
    # Real-time form validation without saving
    case validate_form_params(profile_params) do
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
  def handle_event("save_profile", %{"profile" => profile_params}, socket) do
    # Set loading state immediately
    socket = assign(socket, :saving, true)

    # Convert and validate form parameters
    case convert_form_params_to_attrs(profile_params) do
      {:ok, attrs} ->
        # Attempt to save the profile using the context module
        result =
          case socket.assigns.view_mode do
            :create ->
              Llm.create_profile(attrs)

            :edit ->
              profile_id = socket.assigns.selected_profile.id
              Llm.update_profile(profile_id, attrs)
          end

        case result do
          {:ok, _profile} ->
            action = if socket.assigns.view_mode == :create, do: "created", else: "updated"

            {:noreply,
             socket
             |> assign(:view_mode, :list)
             |> assign(:selected_profile, nil)
             |> assign(:saving, false)
             |> assign(:form_errors, %{})
             |> assign(:validation_errors, %{})
             |> assign(:last_operation, action)
             |> assign(:operation_status, :success)
             |> put_flash(:info, build_success_message(action, attrs[:name]))
             |> load_profiles_data()}

          {:error, reason} when is_binary(reason) ->
            {:noreply,
             socket
             |> assign(:saving, false)
             |> assign(:last_operation, "save")
             |> assign(:operation_status, :error)
             |> put_flash(:error, build_error_message("save", reason))}

          {:error, %Ecto.Changeset{} = changeset} ->
            error_message = format_changeset_errors(changeset)
            field_errors = extract_field_errors(changeset)

            {:noreply,
             socket
             |> assign(:saving, false)
             |> assign(:form_errors, field_errors)
             |> assign(:validation_errors, field_errors)
             |> assign(:last_operation, "save")
             |> assign(:operation_status, :error)
             |> put_flash(:error, build_error_message("validation", error_message))}

          {:error, reason} ->
            {:noreply,
             socket
             |> assign(:saving, false)
             |> assign(:last_operation, "save")
             |> assign(:operation_status, :error)
             |> put_flash(:error, build_error_message("save", inspect(reason)))}
        end

      {:error, validation_errors} when is_list(validation_errors) ->
        error_map = build_error_map(validation_errors)
        error_message = Enum.join(validation_errors, "; ")

        {:noreply,
         socket
         |> assign(:saving, false)
         |> assign(:form_errors, error_map)
         |> assign(:validation_errors, error_map)
         |> assign(:last_operation, "validation")
         |> assign(:operation_status, :error)
         |> put_flash(:error, build_error_message("validation", error_message))}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:saving, false)
         |> assign(:form_errors, %{general: reason})
         |> assign(:validation_errors, %{general: reason})
         |> assign(:last_operation, "validation")
         |> assign(:operation_status, :error)
         |> put_flash(:error, build_error_message("validation", reason))}
    end
  end

  @impl true
  def handle_event("delete_profile", %{"profile_id" => profile_id}, socket) do
    # Set deleting state
    socket = assign(socket, :deleting, true)

    # Get profile name for better error messages
    profile = Enum.find(socket.assigns.all_profiles, &(&1.id == profile_id))
    profile_name = if profile, do: profile.name, else: "Unknown Profile"

    case Llm.delete_profile(profile_id) do
      :ok ->
        {:noreply,
         socket
         |> assign(:deleting, false)
         |> assign(:last_operation, "delete")
         |> assign(:operation_status, :success)
         |> put_flash(:info, build_success_message("deleted", profile_name))
         |> load_profiles_data()}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:deleting, false)
         |> assign(:last_operation, "delete")
         |> assign(:operation_status, :error)
         |> put_flash(:error, build_error_message("delete", reason, profile_name))}
    end
  end

  @impl true
  def handle_event("toggle_status", %{"profile_id" => profile_id}, socket) do
    # Get profile name for better messages
    profile = Enum.find(socket.assigns.all_profiles, &(&1.id == profile_id))
    profile_name = if profile, do: profile.name, else: "Unknown Profile"

    case Llm.toggle_profile_status(profile_id) do
      {:ok, updated_profile} ->
        status = if updated_profile.enabled, do: "activated", else: "deactivated"

        {:noreply,
         socket
         |> assign(:last_operation, "toggle_status")
         |> assign(:operation_status, :success)
         |> put_flash(:info, build_success_message(status, profile_name))
         |> load_profiles_data()}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:last_operation, "toggle_status")
         |> assign(:operation_status, :error)
         |> put_flash(:error, build_error_message("toggle status", reason, profile_name))}
    end
  end

  @impl true
  def handle_event("bulk_action", %{"action" => action, "selected" => selected_json}, socket) do
    case Jason.decode(selected_json) do
      {:ok, selected_ids} when is_list(selected_ids) ->
        case Llm.bulk_action(action, selected_ids) do
          {:ok, result} ->
            {:noreply,
             socket
             |> put_flash(:info, build_bulk_success_message(action, result))
             |> assign(:selected_profiles, [])
             |> assign(:show_bulk_actions, false)
             |> assign(:last_operation, "bulk_#{action}")
             |> assign(:operation_status, :success)
             |> load_profiles_data()}

          {:error, reason} ->
            {:noreply,
             socket
             |> assign(:last_operation, "bulk_#{action}")
             |> assign(:operation_status, :error)
             |> put_flash(:error, build_bulk_error_message(action, reason))}
        end

      {:error, _} ->
        {:noreply,
         socket
         |> assign(:last_operation, "bulk_action")
         |> assign(:operation_status, :error)
         |> put_flash(:error, "Invalid selection data. Please try again.")}
    end
  end

  @impl true
  def handle_event("toggle_profile_selection", %{"profile_id" => profile_id}, socket) do
    selected = socket.assigns.selected_profiles

    new_selected =
      if profile_id in selected do
        List.delete(selected, profile_id)
      else
        [profile_id | selected]
      end

    {:noreply,
     socket
     |> assign(:selected_profiles, new_selected)
     |> assign(:show_bulk_actions, length(new_selected) > 0)}
  end

  @impl true
  def handle_event("toggle_all_profiles", %{"checked" => checked}, socket) do
    new_selected =
      if checked == "true" do
        Enum.map(socket.assigns.filtered_profiles, & &1.id)
      else
        []
      end

    {:noreply,
     socket
     |> assign(:selected_profiles, new_selected)
     |> assign(:show_bulk_actions, length(new_selected) > 0)}
  end

  @impl true
  def handle_event("clear_selection", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_profiles, [])
     |> assign(:show_bulk_actions, false)}
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
      if is_nil(assigns[:available_providers]) do
        assign(assigns, :available_providers, Llm.available_providers())
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
      <!-- Enhanced Flash Messages -->
      <.enhanced_flash
        flash={@flash}
        last_operation={@last_operation}
        operation_status={@operation_status}
      />
      <!-- Header -->
      <div class="mb-8">
        <.header>
          LLM Profiles
          <:subtitle>Manage LLM model configurations, providers, and usage settings</:subtitle>

          <:actions>
            <div class="flex gap-2">
              <button
                :if={@view_mode == :list}
                class="btn btn-primary btn-sm"
                phx-click="create_profile"
              >
                <.icon name="hero-plus" class="size-4 mr-2" /> New Profile
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

      <div class="flex flex-col flex-1 overflow-hidden">
        <div :if={@view_mode == :list} class="flex-1 overflow-auto">
          <.profiles_list
            profiles={@filtered_profiles}
            search_query={@search_query}
            provider_filter={@provider_filter}
            status_filter={@status_filter}
            profile_stats={@profile_stats}
            selected_profiles={@selected_profiles}
            show_bulk_actions={@show_bulk_actions}
            loading={@loading}
            deleting={@deleting}
          />
        </div>

        <div :if={@view_mode == :detail && @selected_profile} class="flex-1 overflow-auto">
          <.profile_detail profile={@selected_profile} />
        </div>

        <div :if={@view_mode in [:edit, :create] && @selected_profile} class="flex-1 overflow-auto">
          <.profile_form
            profile={@selected_profile}
            mode={@view_mode}
            available_providers={@available_providers}
            saving={@saving}
            form_errors={@form_errors}
            validation_errors={@validation_errors}
          />
        </div>
      </div>
    </AdminLayouts.admin>
    """
  end

  # Load profiles data using context module with proper filtering
  defp load_profiles_data(socket) do
    # Set loading state
    socket = assign(socket, :loading, true)

    filters = build_filters(socket)

    case Llm.list_profiles_ui(filters) do
      {:ok, ui_profiles} ->
        stats = Llm.calculate_profile_stats(ui_profiles)
        available_providers = Llm.available_providers()

        socket
        |> assign(:all_profiles, ui_profiles)
        |> assign(:filtered_profiles, ui_profiles)
        |> assign(:profile_stats, stats)
        |> assign(:available_providers, available_providers)
        |> assign(:loading, false)

      {:error, reason} ->
        socket
        |> assign(:all_profiles, [])
        |> assign(:filtered_profiles, [])
        |> assign(:profile_stats, build_empty_stats())
        |> assign(:available_providers, Llm.available_providers())
        |> assign(:loading, false)
        |> assign(:last_operation, "load")
        |> assign(:operation_status, :error)
        |> put_flash(:error, build_error_message("load profiles", reason))
    end
  end

  # Enhanced filtering with improved search across name, model, and tags
  defp filter_profiles(socket) do
    # Since the context module already handles filtering, we just need to reload with new filters
    load_profiles_data(socket)
  end

  # Build comprehensive filters for the context module
  defp build_filters(socket) do
    %{
      q: socket.assigns[:search_query] || "",
      provider: socket.assigns[:provider_filter] || "all",
      status: socket.assigns[:status_filter] || "all"
    }
  end

  # Build empty statistics structure
  defp build_empty_stats do
    # Get available provider types from database
    available_provider_types =
      case AgentWeb.Providers.list_providers() do
        {:ok, providers} ->
          providers
          |> Enum.map(& &1.type)
          |> Enum.uniq()
          |> Enum.map(&String.to_atom/1)
        {:error, _} ->
          [:openai_compatible, :openai, :fake]  # Fallback to registry types
      end

    # Base stats
    base_stats = %{
      total: 0,
      active: 0,
      inactive: 0
    }

    # Add provider type stats
    provider_stats =
      available_provider_types
      |> Enum.map(fn provider -> {provider, 0} end)
      |> Enum.into(%{})

    Map.merge(base_stats, provider_stats)
  end

  # Convert LLMProfile domain struct to UI format
  # defp convert_llm_profile_to_ui_format(%AgentCore.Llm.LLMProfile{} = profile) do
  #   %{
  #     id: profile.id,
  #     name: profile.name,
  #     provider: to_string(profile.provider),
  #     model: profile.model,
  #     status: if(profile.enabled, do: "active", else: "inactive"),
  #     enabled: profile.enabled,
  #     temperature: profile.generation.temperature,
  #     max_tokens: profile.generation.max_output_tokens,
  #     tools: profile.tools,
  #     tags: profile.tags,
  #     created_at: format_datetime(profile.inserted_at),
  #     updated_at: format_datetime(profile.updated_at),
  #     # TODO: Get from actual usage tracking
  #     last_used: "Never",
  #     # TODO: Get from actual usage tracking
  #     usage_count: 0,
  #     config: %{
  #       temperature: profile.generation.temperature,
  #       max_tokens: profile.generation.max_output_tokens,
  #       # Default value since not in domain model
  #       top_p: 1.0,
  #       # Default value since not in domain model
  #       frequency_penalty: 0.0,
  #       # Default value since not in domain model
  #       presence_penalty: 0.0
  #     },
  #     cost_per_1k_tokens: %{
  #       # TODO: Get from provider configuration
  #       input: 0.0,
  #       # TODO: Get from provider configuration
  #       output: 0.0
  #     },
  #     # TODO: Add description field to domain model
  #     description: "",
  #     usage_stats: %{
  #       # TODO: Get from actual usage tracking
  #       total_requests: 0,
  #       total_tokens: 0,
  #       avg_response_time: 0,
  #       success_rate: 100.0
  #     }
  #   }
  # end

  # Enhanced error handling and user experience helper functions

  # Validate form parameters without saving (for real-time validation)
  defp validate_form_params(params) do
    convert_form_params_to_attrs(params)
  end

  # Build error map from validation error list
  defp build_error_map(validation_errors) when is_list(validation_errors) do
    validation_errors
    |> Enum.reduce(%{}, fn error, acc ->
      case String.split(error, ":", parts: 2) do
        [field, message] ->
          field_atom = String.to_atom(String.trim(field))
          Map.put(acc, field_atom, String.trim(message))

        [message] ->
          Map.put(acc, :general, String.trim(message))
      end
    end)
  end

  # Extract field-specific errors from Ecto changeset
  defp extract_field_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  # Build user-friendly success messages
  defp build_success_message(action, name \\ nil)

  defp build_success_message("created", name) when is_binary(name) do
    "Profile '#{name}' has been created successfully! You can now use it for LLM operations."
  end

  defp build_success_message("updated", name) when is_binary(name) do
    "Profile '#{name}' has been updated successfully! Changes are now active."
  end

  defp build_success_message("deleted", name) when is_binary(name) do
    "Profile '#{name}' has been permanently deleted."
  end

  defp build_success_message("activated", name) when is_binary(name) do
    "Profile '#{name}' is now active and available for use."
  end

  defp build_success_message("deactivated", name) when is_binary(name) do
    "Profile '#{name}' has been deactivated and is no longer available for use."
  end

  defp build_success_message(action, _name) do
    "Operation '#{action}' completed successfully."
  end

  # Build user-friendly error messages
  defp build_error_message(operation, reason, name \\ nil)

  defp build_error_message("save", reason, name) when is_binary(name) do
    "Failed to save profile '#{name}': #{reason}. Please check your input and try again."
  end

  defp build_error_message("delete", reason, name) when is_binary(name) do
    "Failed to delete profile '#{name}': #{reason}. The profile may be in use or protected."
  end

  defp build_error_message("toggle status", reason, name) when is_binary(name) do
    "Failed to change status of profile '#{name}': #{reason}. Please try again."
  end

  defp build_error_message("validation", reason, _name) do
    "Validation failed: #{reason}. Please correct the highlighted fields and try again."
  end

  defp build_error_message("load profiles", reason, _name) do
    "Failed to load profiles: #{reason}. Please refresh the page or contact support if the problem persists."
  end

  defp build_error_message(operation, reason, _name) do
    "Failed to #{operation}: #{reason}. Please try again or contact support if the problem persists."
  end

  # Build bulk operation success messages
  defp build_bulk_success_message(action, result) do
    count = Map.get(result, :success_count, 0)

    case action do
      "activate" ->
        "Successfully activated #{count} profile(s). They are now available for use."

      "deactivate" ->
        "Successfully deactivated #{count} profile(s). They are no longer available for use."

      "delete" ->
        "Successfully deleted #{count} profile(s). This action cannot be undone."

      _ ->
        "Bulk operation completed successfully on #{count} profile(s)."
    end
  end

  # Build bulk operation error messages
  defp build_bulk_error_message(action, reason) do
    case action do
      "activate" ->
        "Failed to activate some profiles: #{reason}. Please check individual profiles and try again."

      "deactivate" ->
        "Failed to deactivate some profiles: #{reason}. Some profiles may be protected or in use."

      "delete" ->
        "Failed to delete some profiles: #{reason}. Some profiles may be protected or in use."

      _ ->
        "Bulk operation failed: #{reason}. Please try again or contact support."
    end
  end

  # Enhanced flash message component with better styling, auto-dismiss, and accessibility
  attr :flash, :map, required: true
  attr :last_operation, :string, default: nil
  attr :operation_status, :atom, default: nil

  defp enhanced_flash(assigns) do
    ~H"""
    <!-- Success Flash with Auto-dismiss -->
    <div
      :if={Phoenix.Flash.get(@flash, :info)}
      class="alert alert-success shadow-lg mb-4 animate-in slide-in-from-top-2 duration-300"
      id="success-flash"
      phx-hook="AutoDismissFlash"
      data-dismiss-delay="5000"
      role="alert"
      aria-live="polite"
    >
      <div class="flex items-center gap-3">
        <.icon name="hero-check-circle" class="size-6 text-success flex-shrink-0" />
        <div class="flex-1 min-w-0">
          <div class="font-medium">Success!</div>

          <div class="text-sm opacity-90 break-words">{Phoenix.Flash.get(@flash, :info)}</div>

          <div :if={@last_operation} class="text-xs opacity-70 mt-1">
            Operation: {String.capitalize(@last_operation || "unknown")}
          </div>
        </div>

        <button
          class="btn btn-ghost btn-sm hover:bg-success-focus focus:bg-success-focus"
          onclick="this.parentElement.parentElement.style.display='none'"
          aria-label="Dismiss success message"
          title="Dismiss (or wait 5 seconds)"
        >
          <.icon name="hero-x-mark" class="size-4" />
        </button>
      </div>
      <!-- Progress bar for auto-dismiss -->
      <div class="absolute bottom-0 left-0 h-1 bg-success-content/20 w-full">
        <div class="h-full bg-success-content/60 animate-shrink-width"></div>
      </div>
    </div>
    <!-- Error Flash (no auto-dismiss for errors) -->
    <div
      :if={Phoenix.Flash.get(@flash, :error)}
      class="alert alert-error shadow-lg mb-4 animate-in slide-in-from-top-2 duration-300"
      id="error-flash"
      role="alert"
      aria-live="assertive"
    >
      <div class="flex items-center gap-3">
        <.icon name="hero-exclamation-triangle" class="size-6 text-error flex-shrink-0" />
        <div class="flex-1 min-w-0">
          <div class="font-medium">Error</div>

          <div class="text-sm opacity-90 break-words">{Phoenix.Flash.get(@flash, :error)}</div>

          <div :if={@last_operation} class="text-xs opacity-70 mt-1">
            Operation: {String.capitalize(@last_operation || "unknown")}
          </div>

          <div class="text-xs opacity-70 mt-1">
            Please review the details above and try again. Contact support if the problem persists.
          </div>
        </div>

        <button
          class="btn btn-ghost btn-sm hover:bg-error-focus focus:bg-error-focus"
          onclick="this.parentElement.parentElement.style.display='none'"
          aria-label="Dismiss error message"
          title="Dismiss error message"
        >
          <.icon name="hero-x-mark" class="size-4" />
        </button>
      </div>
    </div>
    <!-- Warning Flash with Auto-dismiss -->
    <div
      :if={Phoenix.Flash.get(@flash, :warning)}
      class="alert alert-warning shadow-lg mb-4 animate-in slide-in-from-top-2 duration-300"
      id="warning-flash"
      phx-hook="AutoDismissFlash"
      data-dismiss-delay="7000"
      role="alert"
      aria-live="polite"
    >
      <div class="flex items-center gap-3">
        <.icon name="hero-exclamation-triangle" class="size-6 text-warning flex-shrink-0" />
        <div class="flex-1 min-w-0">
          <div class="font-medium">Warning</div>

          <div class="text-sm opacity-90 break-words">{Phoenix.Flash.get(@flash, :warning)}</div>
        </div>

        <button
          class="btn btn-ghost btn-sm hover:bg-warning-focus focus:bg-warning-focus"
          onclick="this.parentElement.parentElement.style.display='none'"
          aria-label="Dismiss warning message"
          title="Dismiss (or wait 7 seconds)"
        >
          <.icon name="hero-x-mark" class="size-4" />
        </button>
      </div>
      <!-- Progress bar for auto-dismiss -->
      <div class="absolute bottom-0 left-0 h-1 bg-warning-content/20 w-full">
        <div class="h-full bg-warning-content/60 animate-shrink-width"></div>
      </div>
    </div>
    <!-- Custom CSS for animations -->
    <style>
      @keyframes shrink-width {
        from { width: 100%; }
        to { width: 0%; }
      }
      .animate-shrink-width {
        animation: shrink-width 5s linear forwards;
      }
      .alert[data-dismiss-delay="7000"] .animate-shrink-width {
        animation-duration: 7s;
      }
    </style>
    """
  end

  # Helper function to format datetime
  defp format_datetime(nil), do: "Never"

  defp format_datetime(datetime) do
    case DateTime.from_naive(datetime, "Etc/UTC") do
      {:ok, dt} -> Calendar.strftime(dt, "%Y-%m-%d")
      _ -> "Unknown"
    end
  end

  # Check if there are additional providers beyond the main ones
  defp has_additional_providers?(stats) do
    # Get all provider types except the main ones we always show
    main_providers = [:total, :active, :inactive, :openai_compatible, :openai, :fake]

    stats
    |> Map.keys()
    |> Enum.reject(&(&1 in main_providers))
    |> Enum.any?(fn provider -> Map.get(stats, provider, 0) > 0 end)
  end

  # Get provider options with counts for the filter dropdown
  defp get_provider_options(stats) do
    # Get all available providers from context module
    available_providers = Llm.available_providers()

    # Add counts to each provider and filter out those with 0 profiles
    available_providers
    |> Enum.map(fn provider ->
      count = Map.get(stats, String.to_atom(provider.value), 0)
      Map.put(provider, :count, count)
    end)
    |> Enum.filter(fn provider -> provider.count > 0 end)
    |> Enum.sort_by(fn provider -> provider.count end, :desc)
  end

  defp get_empty_profile do
    %{
      id: nil,
      name: "",
      model: "",
      provider_id: nil,  # Changed from provider to provider_id
      enabled: true,
      policy_version: "1",
      description: "",
      generation: %{
        temperature: 0.7,
        top_p: 1.0,
        max_output_tokens: 2048,
        seed: nil,
        presence_penalty: 0.0,
        frequency_penalty: 0.0,
        stop: []
      },
      budgets: %{
        max_input_tokens: nil,
        max_output_tokens: nil,
        max_total_tokens: nil,
        max_cost_eur: nil,
        max_steps: nil
      },
      tools: [],
      stop_list: [],
      tags: [],
      # Legacy fields for backward compatibility
      status: "active",
      temperature: 0.7,
      max_tokens: 2048,
      created_at: nil,
      updated_at: nil,
      usage_stats: %{
        total_requests: 0,
        total_tokens: 0,
        avg_response_time: 0,
        success_rate: 100.0
      },
      config: %{
        temperature: 0.7,
        max_tokens: 2048,
        top_p: 1.0,
        frequency_penalty: 0.0,
        presence_penalty: 0.0,
        seed: nil
      },
      cost_per_1k_tokens: %{
        input: 0.0,
        output: 0.0
      }
    }
  end

  # Convert UI profile format to form-compatible format for proper pre-population
  # This ensures that nested data structures (generation, budgets) are properly formatted
  # for form inputs and handles null values appropriately
  defp convert_ui_profile_to_form_format(nil), do: get_empty_profile()

  defp convert_ui_profile_to_form_format(ui_profile) when is_map(ui_profile) do
    # Extract generation parameters from both new and legacy formats
    generation = %{
      temperature:
        get_nested_value(
          ui_profile,
          [:generation, :temperature],
          [:config, :temperature],
          [:temperature],
          0.7
        ),
      top_p: get_nested_value(ui_profile, [:generation, :top_p], [:config, :top_p], nil, 1.0),
      max_output_tokens:
        get_nested_value(
          ui_profile,
          [:generation, :max_output_tokens],
          [:config, :max_tokens],
          [:max_tokens],
          2048
        ),
      seed: get_nested_value(ui_profile, [:generation, :seed], [:config, :seed], nil, nil),
      presence_penalty:
        get_nested_value(
          ui_profile,
          [:generation, :presence_penalty],
          [:config, :presence_penalty],
          nil,
          0.0
        ),
      frequency_penalty:
        get_nested_value(
          ui_profile,
          [:generation, :frequency_penalty],
          [:config, :frequency_penalty],
          nil,
          0.0
        ),
      stop: get_nested_value(ui_profile, [:generation, :stop], [:stop_list], nil, [])
    }

    # Extract budget parameters with proper null handling
    budgets = %{
      max_input_tokens:
        get_nested_value(ui_profile, [:budgets, :max_input_tokens], nil, nil, nil),
      max_output_tokens:
        get_nested_value(ui_profile, [:budgets, :max_output_tokens], nil, nil, nil),
      max_total_tokens:
        get_nested_value(ui_profile, [:budgets, :max_total_tokens], nil, nil, nil),
      max_cost_eur: get_nested_value(ui_profile, [:budgets, :max_cost_eur], nil, nil, nil),
      max_steps: get_nested_value(ui_profile, [:budgets, :max_steps], nil, nil, nil)
    }

    # Build form-compatible profile with proper nested structure
    %{
      id: Map.get(ui_profile, :id),
      name: Map.get(ui_profile, :name, ""),
      model: Map.get(ui_profile, :model, ""),
      provider_id: Map.get(ui_profile, :provider_id, nil),  # Changed from provider to provider_id
      enabled: Map.get(ui_profile, :enabled, true),
      policy_version: Map.get(ui_profile, :policy_version, "1"),
      description: Map.get(ui_profile, :description, ""),

      # Properly structured nested data
      generation: generation,
      budgets: budgets,

      # Tools and configuration with safe list handling
      tools: safe_list_for_form(Map.get(ui_profile, :tools, [])),
      stop_list: safe_list_for_form(Map.get(ui_profile, :stop_list, [])),
      tags: safe_list_for_form(Map.get(ui_profile, :tags, [])),

      # Legacy fields for backward compatibility
      status: Map.get(ui_profile, :status, "active"),
      temperature: generation.temperature,
      max_tokens: generation.max_output_tokens,
      created_at: Map.get(ui_profile, :created_at),
      updated_at: Map.get(ui_profile, :updated_at),

      # Preserve other UI fields
      usage_stats: Map.get(ui_profile, :usage_stats, %{}),
      config: %{
        temperature: generation.temperature,
        max_tokens: generation.max_output_tokens,
        top_p: generation.top_p,
        frequency_penalty: generation.frequency_penalty,
        presence_penalty: generation.presence_penalty,
        seed: generation.seed
      },
      cost_per_1k_tokens: Map.get(ui_profile, :cost_per_1k_tokens, %{input: 0.0, output: 0.0})
    }
  end

  # Helper to get nested values with multiple fallback paths and default
  defp get_nested_value(map, primary_path, secondary_path, tertiary_path, default) do
    cond do
      primary_path && get_in(map, primary_path) != nil -> get_in(map, primary_path)
      secondary_path && get_in(map, secondary_path) != nil -> get_in(map, secondary_path)
      tertiary_path && get_in(map, tertiary_path) != nil -> get_in(map, tertiary_path)
      true -> default
    end
  end

  # Helper to safely convert lists for form display
  defp safe_list_for_form(nil), do: []
  defp safe_list_for_form(list) when is_list(list), do: list
  defp safe_list_for_form(_), do: []

  # Components
  attr :profiles, :list, required: true
  attr :search_query, :string, required: true
  attr :provider_filter, :string, required: true
  attr :status_filter, :string, required: true
  attr :profile_stats, :map, required: true
  attr :selected_profiles, :list, required: true
  attr :show_bulk_actions, :boolean, required: true
  attr :loading, :boolean, default: false
  attr :deleting, :boolean, default: false

  defp profiles_list(assigns) do
    ~H"""
    <div class="flex flex-col h-full space-y-4">
      <!-- Loading Overlay for List -->
      <div
        :if={@loading}
        class="absolute inset-0 bg-base-100/50 backdrop-blur-sm flex items-center justify-center z-50 rounded-lg"
      >
        <div class="flex flex-col items-center gap-4">
          <span class="loading loading-spinner loading-lg text-primary"></span>
          <p class="text-base-content/70 font-medium">Loading profiles...</p>
        </div>
      </div>
      <!-- Profile Statistics -->
      <div class="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-6 gap-2">
        <.stat_card title="Total" value={@profile_stats.total} color="primary" />
        <.stat_card title="Active" value={@profile_stats.active} color="success" />
        <.stat_card title="Inactive" value={@profile_stats.inactive} color="warning" />
        <.stat_card title="OpenAI Compatible" value={Map.get(@profile_stats, :openai_compatible, 0)} color="info" />
        <.stat_card title="OpenAI" value={Map.get(@profile_stats, :openai, 0)} color="primary" />
        <.stat_card title="Fake" value={Map.get(@profile_stats, :fake, 0)} color="warning" />
      </div>
      <!-- Additional Provider Statistics (if any exist) -->
      <div
        :if={has_additional_providers?(@profile_stats)}
        class="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-6 gap-2"
      >
        <%= for {provider_type, count} <- @profile_stats do %>
          <.stat_card
            :if={provider_type not in [:total, :active, :inactive, :openai_compatible, :openai, :fake] && count > 0}
            title={String.capitalize(to_string(provider_type))}
            value={count}
            color="secondary"
          />
        <% end %>
      </div>
      <!-- Filters and Search - Stick στο πάνω μέρος -->
      <div class="sticky top-0 z-10 bg-base-100 pt-2 pb-4 space-y-4 border-b">
        <div class="flex flex-wrap gap-3 items-center">
          <div class="form-control flex-1 min-w-[200px]">
            <input
              type="text"
              placeholder="Search profiles..."
              class="input input-bordered input-sm w-full"
              value={@search_query}
              phx-change="search_profiles"
              phx-value-search={@search_query}
              phx-debounce="300"
            />
          </div>

          <div class="form-control">
            <select
              class="select select-bordered select-sm w-40"
              phx-change="filter_by_provider"
            >
              <option value="all" selected={@provider_filter == "all"}>All Providers</option>

              <option
                :for={provider <- get_provider_options(@profile_stats)}
                value={provider.value}
                selected={@provider_filter == provider.value}
              >
                {provider.label} ({provider.count})
              </option>
            </select>
          </div>

          <div class="form-control">
            <select
              class="select select-bordered select-sm w-32"
              phx-change="filter_by_status"
            >
              <option value="all" selected={@status_filter == "all"}>All Status</option>

              <option value="active" selected={@status_filter == "active"}>Active</option>

              <option value="inactive" selected={@status_filter == "inactive"}>Inactive</option>
            </select>
          </div>
        </div>
      </div>
      <!-- Profiles Table Container - Παίρνει το υπόλοιπο ύψος -->
      <div class="flex-1 overflow-hidden min-h-0">
        <!-- Bulk Actions Bar -->
        <div
          :if={@show_bulk_actions}
          class="bg-primary text-primary-content p-3 rounded-t-lg flex items-center justify-between"
        >
          <div class="flex items-center gap-3">
            <span class="font-medium">{length(@selected_profiles)} profiles selected</span>
            <button
              class="btn btn-sm btn-ghost text-primary-content hover:bg-primary-focus"
              phx-click="clear_selection"
            >
              Clear Selection
            </button>
          </div>

          <div class="flex gap-2">
            <button
              class="btn btn-sm btn-success"
              phx-click="bulk_action"
              phx-value-action="activate"
              phx-value-selected={Jason.encode!(@selected_profiles)}
            >
              <.icon name="hero-check-circle" class="size-4 mr-1" /> Activate
            </button>
            <button
              class="btn btn-sm btn-warning"
              phx-click="bulk_action"
              phx-value-action="deactivate"
              phx-value-selected={Jason.encode!(@selected_profiles)}
            >
              <.icon name="hero-x-circle" class="size-4 mr-1" /> Deactivate
            </button>
            <button
              class="btn btn-sm btn-error"
              phx-click="bulk_action"
              phx-value-action="delete"
              phx-value-selected={Jason.encode!(@selected_profiles)}
              onclick="return confirm('Are you sure you want to delete the selected profiles? This action cannot be undone.')"
            >
              <.icon name="hero-trash" class="size-4 mr-1" /> Delete
            </button>
          </div>
        </div>

        <div class={["card bg-base-200 shadow-sm h-full", @show_bulk_actions && "rounded-t-none"]}>
          <div class="card-body p-0 h-full">
            <div class="overflow-auto h-full">
              <table class="table table-sm table-pin-rows">
                <thead>
                  <tr class="sticky top-0 bg-base-200 z-10">
                    <th class="w-12">
                      <input
                        type="checkbox"
                        class="checkbox checkbox-sm"
                        phx-click="toggle_all_profiles"
                        phx-value-checked={
                          length(@selected_profiles) == length(@profiles) and length(@profiles) > 0
                        }
                        checked={
                          length(@selected_profiles) == length(@profiles) and length(@profiles) > 0
                        }
                      />
                    </th>

                    <th>Profile</th>

                    <th>Provider</th>

                    <th>Status</th>

                    <th>Usage</th>

                    <th>Last Used</th>

                    <th class="w-32">Actions</th>
                  </tr>
                </thead>

                <tbody>
                  <tr :for={profile <- @profiles} class="hover">
                    <td>
                      <input
                        type="checkbox"
                        class="checkbox checkbox-sm"
                        phx-click="toggle_profile_selection"
                        phx-value-profile_id={profile.id}
                        checked={profile.id in @selected_profiles}
                      />
                    </td>

                    <td>
                      <div class="flex items-center gap-3">
                        <div class="avatar placeholder">
                          <div class="bg-neutral text-neutral-content rounded-full w-8">
                            <span class="text-xs">{String.first(profile.name)}</span>
                          </div>
                        </div>

                        <div>
                          <div class="font-medium">{profile.name}</div>

                          <div class="text-sm text-base-content/70">{profile.model}</div>
                        </div>
                      </div>
                    </td>

                    <td><.provider_badge provider={profile.provider} /></td>

                    <td><.status_badge status={profile.status} /></td>

                    <td class="text-sm">{Map.get(profile, :usage_count, 0)}</td>

                    <td class="text-sm">{Map.get(profile, :last_used, "Never")}</td>

                    <td>
                      <div class="flex gap-1">
                        <button
                          class="btn btn-ghost btn-xs"
                          phx-click="view_profile"
                          phx-value-profile_id={profile.id}
                          title="View Profile"
                        >
                          <.icon name="hero-eye" class="size-3" />
                        </button>
                        <button
                          class="btn btn-ghost btn-xs"
                          phx-click="edit_profile"
                          phx-value-profile_id={profile.id}
                          title="Edit Profile"
                        >
                          <.icon name="hero-pencil" class="size-3" />
                        </button>
                        <button
                          class={[
                            "btn btn-xs",
                            if(profile.status == "active", do: "btn-warning", else: "btn-success")
                          ]}
                          phx-click="toggle_status"
                          phx-value-profile_id={profile.id}
                          title={
                            if profile.status == "active",
                              do: "Deactivate Profile",
                              else: "Activate Profile"
                          }
                        >
                          <.icon
                            name={if profile.status == "active", do: "hero-pause", else: "hero-play"}
                            class="size-3"
                          />
                        </button>
                        <button
                          class={["btn btn-error btn-xs", @deleting && "loading"]}
                          phx-click="delete_profile"
                          phx-value-profile_id={profile.id}
                          onclick={"return confirm('Are you sure you want to delete the profile \"#{profile.name}\"? This action cannot be undone.')"}
                          title="Delete Profile"
                          disabled={@deleting}
                        >
                          <.icon :if={!@deleting} name="hero-trash" class="size-3" /> {if @deleting,
                            do: "",
                            else: ""}
                        </button>
                      </div>
                    </td>
                  </tr>
                  <!-- Empty state -->
                  <tr :if={Enum.empty?(@profiles)}>
                    <td colspan="7" class="text-center py-8">
                      <div class="flex flex-col items-center justify-center">
                        <.icon
                          name="hero-document-magnifying-glass"
                          class="size-12 text-base-content/30 mb-4"
                        />
                        <p class="text-base-content/70">No profiles found</p>

                        <p class="text-sm text-base-content/50">
                          Try adjusting your search or filters
                        </p>
                      </div>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :profile, :map, required: true

  defp profile_detail(assigns) do
    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
      <!-- Profile Info -->
      <div class="lg:col-span-2 space-y-6">
        <div class="card bg-base-200 shadow-sm">
          <div class="card-body">
            <div class="flex items-start gap-4">
              <div class="avatar placeholder">
                <div class="bg-neutral text-neutral-content rounded-full w-16">
                  <span class="text-xl">{String.first(@profile.name)}</span>
                </div>
              </div>

              <div class="flex-1">
                <h3 class="text-xl font-semibold">{@profile.name}</h3>

                <p class="text-base-content/70">{@profile.model}</p>

                <div class="flex gap-2 mt-2">
                  <.provider_badge provider={@profile.provider} />
                  <.status_badge status={@profile.status} />
                </div>
              </div>

              <button
                class="btn btn-outline btn-sm"
                phx-click="edit_profile"
                phx-value-profile_id={@profile.id}
              >
                <.icon name="hero-pencil" class="size-4 mr-2" /> Edit
              </button>
            </div>
          </div>
        </div>
        <!-- Model Configuration -->
        <div class="card bg-base-200 shadow-sm">
          <div class="card-body">
            <h4 class="card-title text-lg">Model Configuration</h4>

            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <p class="text-sm text-base-content/70">Model</p>

                <p class="font-medium">{@profile.model}</p>
              </div>

              <div>
                <p class="text-sm text-base-content/70">Provider</p>

                <p class="font-medium">{String.capitalize(@profile.provider)}</p>
              </div>

              <div>
                <p class="text-sm text-base-content/70">Temperature</p>

                <p class="font-medium">{@profile.config.temperature}</p>
              </div>

              <div>
                <p class="text-sm text-base-content/70">Max Tokens</p>

                <p class="font-medium">{@profile.config.max_tokens}</p>
              </div>

              <div>
                <p class="text-sm text-base-content/70">Top P</p>

                <p class="font-medium">{@profile.config.top_p}</p>
              </div>

              <div>
                <p class="text-sm text-base-content/70">Frequency Penalty</p>

                <p class="font-medium">{@profile.config.frequency_penalty}</p>
              </div>
            </div>
          </div>
        </div>
        <!-- Cost Information -->
        <div class="card bg-base-200 shadow-sm">
          <div class="card-body">
            <h4 class="card-title text-lg">Cost Information</h4>

            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <p class="text-sm text-base-content/70">Input Cost (per 1K tokens)</p>

                <p class="font-medium">${@profile.cost_per_1k_tokens.input}</p>
              </div>

              <div>
                <p class="text-sm text-base-content/70">Output Cost (per 1K tokens)</p>

                <p class="font-medium">${@profile.cost_per_1k_tokens.output}</p>
              </div>
            </div>
          </div>
        </div>
      </div>
      <!-- Usage Stats -->
      <div class="space-y-6">
        <div class="card bg-base-200 shadow-sm">
          <div class="card-body">
            <h4 class="card-title text-lg">Usage Statistics</h4>

            <div class="space-y-4">
              <div>
                <p class="text-sm text-base-content/70">Created</p>

                <p class="font-medium">{@profile.created_at}</p>
              </div>

              <div>
                <p class="text-sm text-base-content/70">Last Used</p>

                <p class="font-medium">{Map.get(@profile, :last_used, "Never")}</p>
              </div>

              <div>
                <p class="text-sm text-base-content/70">Total Usage</p>

                <p class="font-medium">{Map.get(@profile, :usage_count, 0)} requests</p>
              </div>
            </div>
          </div>
        </div>
        <!-- Quick Actions -->
        <div class="card bg-base-200 shadow-sm">
          <div class="card-body">
            <h4 class="card-title text-lg">Quick Actions</h4>

            <div class="space-y-2">
              <button
                class="btn btn-outline btn-sm w-full"
                phx-click="toggle_status"
                phx-value-profile_id={@profile.id}
              >
                <.icon name="hero-power" class="size-4 mr-2" /> {if @profile.status == "active",
                  do: "Deactivate",
                  else: "Activate"}
              </button>
              <button class="btn btn-outline btn-sm w-full">
                <.icon name="hero-arrow-path" class="size-4 mr-2" /> Test Connection
              </button>
              <button class="btn btn-outline btn-sm w-full">
                <.icon name="hero-document-duplicate" class="size-4 mr-2" /> Clone Profile
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :profile, :map, required: true
  attr :mode, :atom, required: true
  attr :available_providers, :list, required: true
  attr :saving, :boolean, default: false
  attr :form_errors, :map, default: %{}
  attr :validation_errors, :map, default: %{}

  defp profile_form(assigns) do
    ~H"""
    <div class="card bg-base-200 shadow-sm max-w-4xl mx-auto">
      <div class="card-body">
        <h3 class="card-title text-lg">
          {if @mode == :create, do: "Create New Profile", else: "Edit Profile"}
        </h3>
        <!-- Loading Overlay -->
        <div
          :if={@saving}
          class="absolute inset-0 bg-base-100/50 backdrop-blur-sm flex items-center justify-center z-50 rounded-lg"
        >
          <div class="flex flex-col items-center gap-4">
            <span class="loading loading-spinner loading-lg text-primary"></span>
            <p class="text-base-content/70 font-medium">
              {if @mode == :create, do: "Creating profile...", else: "Saving changes..."}
            </p>
          </div>
        </div>
        <!-- General Error Alert -->
        <div :if={Map.has_key?(@form_errors, :general)} class="alert alert-error mb-4">
          <.icon name="hero-exclamation-triangle" class="size-5" />
          <span>{@form_errors.general}</span>
        </div>

        <form
          phx-submit="save_profile"
          phx-change="validate_profile"
          class="space-y-6"
          id="profile-form"
          phx-hook="FormKeyboardShortcuts"
          data-save-shortcut="ctrl+s,cmd+s"
          data-cancel-shortcut="escape"
        >
          <!-- Basic Information Section -->
          <div class="card bg-base-100 shadow-sm">
            <div class="card-body">
              <h4 class="card-title text-base mb-4">Basic Information</h4>

              <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div class="form-control">
                  <label class="label">
                    <span class="label-text">Name <span class="text-error">*</span></span>
                    <span :if={Map.has_key?(@form_errors, :name)} class="label-text-alt text-error">
                      <.icon name="hero-exclamation-triangle" class="size-3 inline mr-1" />
                      Required field
                    </span>
                  </label>
                  <div class="relative">
                    <input
                      type="text"
                      name="profile[name]"
                      value={@profile.name}
                      class={[
                        "input input-bordered w-full",
                        Map.has_key?(@form_errors, :name) &&
                          "input-error border-error focus:border-error",
                        !Map.has_key?(@form_errors, :name) && @profile.name != "" &&
                          "input-success border-success"
                      ]}
                      placeholder="e.g., GPT-4 Production"
                      required
                      disabled={@saving}
                      aria-describedby="name-help"
                      aria-invalid={Map.has_key?(@form_errors, :name)}
                    />
                    <!-- Success indicator -->
                    <div
                      :if={!Map.has_key?(@form_errors, :name) && @profile.name != ""}
                      class="absolute inset-y-0 right-0 flex items-center pr-3"
                    >
                      <.icon name="hero-check-circle" class="size-5 text-success" />
                    </div>
                    <!-- Error indicator -->
                    <div
                      :if={Map.has_key?(@form_errors, :name)}
                      class="absolute inset-y-0 right-0 flex items-center pr-3"
                    >
                      <.icon name="hero-exclamation-circle" class="size-5 text-error" />
                    </div>
                  </div>

                  <label class="label" id="name-help">
                    <span class={[
                      "label-text-alt",
                      Map.has_key?(@form_errors, :name) && "text-error",
                      !Map.has_key?(@form_errors, :name) && "text-base-content/70"
                    ]}>
                      {Map.get(@form_errors, :name, "Unique identifier for this profile")}
                    </span>
                  </label>
                </div>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text">Model <span class="text-error">*</span></span>
                    <span :if={Map.has_key?(@form_errors, :model)} class="label-text-alt text-error">
                      <.icon name="hero-exclamation-triangle" class="size-3 inline mr-1" />
                      Required field
                    </span>
                  </label>
                  <div class="relative">
                    <input
                      type="text"
                      name="profile[model]"
                      value={@profile.model}
                      class={[
                        "input input-bordered w-full",
                        Map.has_key?(@form_errors, :model) &&
                          "input-error border-error focus:border-error",
                        !Map.has_key?(@form_errors, :model) && @profile.model != "" &&
                          "input-success border-success"
                      ]}
                      placeholder="e.g., gpt-4-turbo, claude-3-opus"
                      required
                      disabled={@saving}
                      aria-describedby="model-help"
                      aria-invalid={Map.has_key?(@form_errors, :model)}
                    />
                    <!-- Success indicator -->
                    <div
                      :if={!Map.has_key?(@form_errors, :model) && @profile.model != ""}
                      class="absolute inset-y-0 right-0 flex items-center pr-3"
                    >
                      <.icon name="hero-check-circle" class="size-5 text-success" />
                    </div>
                    <!-- Error indicator -->
                    <div
                      :if={Map.has_key?(@form_errors, :model)}
                      class="absolute inset-y-0 right-0 flex items-center pr-3"
                    >
                      <.icon name="hero-exclamation-circle" class="size-5 text-error" />
                    </div>
                  </div>

                  <label class="label" id="model-help">
                    <span class={[
                      "label-text-alt",
                      Map.has_key?(@form_errors, :model) && "text-error",
                      !Map.has_key?(@form_errors, :model) && "text-base-content/70"
                    ]}>
                      {Map.get(@form_errors, :model, "Specific model identifier from provider")}
                    </span>
                  </label>
                </div>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text">Provider <span class="text-error">*</span></span>
                    <span
                      :if={Map.has_key?(@form_errors, :provider_id)}
                      class="label-text-alt text-error"
                    >
                      <.icon name="hero-exclamation-triangle" class="size-3 inline mr-1" />
                      Required field
                    </span>
                  </label>
                  <div class="relative">
                    <select
                      name="profile[provider_id]"
                      class={[
                        "select select-bordered w-full",
                        Map.has_key?(@form_errors, :provider_id) &&
                          "select-error border-error focus:border-error",
                        !Map.has_key?(@form_errors, :provider_id) && @profile.provider_id != nil &&
                          "select-success border-success"
                      ]}
                      required
                      disabled={@saving}
                      aria-describedby="provider-help"
                      aria-invalid={Map.has_key?(@form_errors, :provider_id)}
                    >
                      <option value="" disabled>Select a provider</option>

                      <option
                        :for={provider <- @available_providers}
                        value={provider.value}
                        selected={provider.value == @profile.provider_id}
                      >
                        {provider.label} - {provider.description}
                      </option>
                    </select>
                    <!-- Success indicator -->
                    <div
                      :if={!Map.has_key?(@form_errors, :provider_id) && @profile.provider_id != nil}
                      class="absolute inset-y-0 right-8 flex items-center pr-3 pointer-events-none"
                    >
                      <.icon name="hero-check-circle" class="size-5 text-success" />
                    </div>
                    <!-- Error indicator -->
                    <div
                      :if={Map.has_key?(@form_errors, :provider_id)}
                      class="absolute inset-y-0 right-8 flex items-center pr-3 pointer-events-none"
                    >
                      <.icon name="hero-exclamation-circle" class="size-5 text-error" />
                    </div>
                  </div>

                  <label class="label" id="provider-help">
                    <span class={[
                      "label-text-alt",
                      Map.has_key?(@form_errors, :provider_id) && "text-error",
                      !Map.has_key?(@form_errors, :provider_id) && "text-base-content/70"
                    ]}>
                      {Map.get(@form_errors, :provider_id, "Choose your LLM provider service")}
                    </span>
                  </label>
                </div>

                <div class="form-control">
                  <label class="label"><span class="label-text">Status</span></label>
                  <select name="profile[enabled]" class="select select-bordered" disabled={@saving}>
                    <option value="true" selected={@profile.enabled == true}>Active</option>

                    <option value="false" selected={@profile.enabled == false}>Inactive</option>
                  </select>
                </div>

                <div class="form-control md:col-span-2">
                  <label class="label"><span class="label-text">Description</span></label> <textarea
                    name="profile[description]"
                    class="textarea textarea-bordered"
                    rows="3"
                    placeholder="Optional description of this profile's purpose and usage"
                    disabled={@saving}
                  >{Map.get(@profile, :description, "")}</textarea>
                </div>
              </div>
            </div>
          </div>
          <!-- Provider Configuration Hints -->
          <div :if={@profile.provider && @profile.provider != ""} class="card bg-base-100 shadow-sm">
            <div class="card-body">
              <h4 class="card-title text-base mb-4">
                <.icon name="hero-information-circle" class="size-5 mr-2" />
                Provider Configuration Hints
              </h4>

              <.provider_config_hints
                provider={@profile.provider || to_string(@profile.provider_id)}
                available_providers={@available_providers}
              />
            </div>
          </div>
          <!-- Generation Parameters Section -->
          <div class="card bg-base-100 shadow-sm">
            <div class="card-body">
              <h4 class="card-title text-base mb-4">Generation Parameters</h4>

              <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                <div class="form-control">
                  <label class="label"><span class="label-text">Temperature</span></label>
                  <input
                    type="number"
                    name="profile[generation][temperature]"
                    value={
                      get_in(@profile, [:generation, :temperature]) ||
                        get_in(@profile, [:config, :temperature]) || 0.7
                    }
                    class={[
                      "input input-bordered",
                      Map.has_key?(@form_errors, :temperature) && "input-error"
                    ]}
                    step="0.1"
                    min="0"
                    max="2"
                    placeholder="0.7"
                    disabled={@saving}
                  />
                  <label class="label">
                    <span class={[
                      "label-text-alt",
                      Map.has_key?(@form_errors, :temperature) && "text-error"
                    ]}>
                      {Map.get(@form_errors, :temperature, "0.0 = deterministic, 2.0 = very creative")}
                    </span>
                  </label>
                </div>

                <div class="form-control">
                  <label class="label"><span class="label-text">Top P</span></label>
                  <input
                    type="number"
                    name="profile[generation][top_p]"
                    value={
                      get_in(@profile, [:generation, :top_p]) || get_in(@profile, [:config, :top_p]) ||
                        1.0
                    }
                    class={[
                      "input input-bordered",
                      Map.has_key?(@form_errors, :top_p) && "input-error"
                    ]}
                    step="0.1"
                    min="0"
                    max="1"
                    placeholder="1.0"
                    disabled={@saving}
                  />
                  <label class="label">
                    <span class={[
                      "label-text-alt",
                      Map.has_key?(@form_errors, :top_p) && "text-error"
                    ]}>
                      {Map.get(@form_errors, :top_p, "Nucleus sampling parameter")}
                    </span>
                  </label>
                </div>

                <div class="form-control">
                  <label class="label"><span class="label-text">Max Output Tokens</span></label>
                  <input
                    type="number"
                    name="profile[generation][max_output_tokens]"
                    value={
                      get_in(@profile, [:generation, :max_output_tokens]) ||
                        get_in(@profile, [:config, :max_tokens]) || 2048
                    }
                    class={[
                      "input input-bordered",
                      Map.has_key?(@form_errors, :max_output_tokens) && "input-error"
                    ]}
                    min="1"
                    max="32000"
                    placeholder="2048"
                    disabled={@saving}
                  />
                  <label class="label">
                    <span class={[
                      "label-text-alt",
                      Map.has_key?(@form_errors, :max_output_tokens) && "text-error"
                    ]}>
                      {Map.get(@form_errors, :max_output_tokens, "Maximum tokens in response")}
                    </span>
                  </label>
                </div>

                <div class="form-control">
                  <label class="label"><span class="label-text">Presence Penalty</span></label>
                  <input
                    type="number"
                    name="profile[generation][presence_penalty]"
                    value={
                      get_in(@profile, [:generation, :presence_penalty]) ||
                        get_in(@profile, [:config, :presence_penalty]) || 0.0
                    }
                    class={[
                      "input input-bordered",
                      Map.has_key?(@form_errors, :presence_penalty) && "input-error"
                    ]}
                    step="0.1"
                    min="-2"
                    max="2"
                    placeholder="0.0"
                    disabled={@saving}
                  />
                  <label class="label">
                    <span class={[
                      "label-text-alt",
                      Map.has_key?(@form_errors, :presence_penalty) && "text-error"
                    ]}>
                      {Map.get(
                        @form_errors,
                        :presence_penalty,
                        "Penalty for new topics (-2.0 to 2.0)"
                      )}
                    </span>
                  </label>
                </div>

                <div class="form-control">
                  <label class="label"><span class="label-text">Frequency Penalty</span></label>
                  <input
                    type="number"
                    name="profile[generation][frequency_penalty]"
                    value={
                      get_in(@profile, [:generation, :frequency_penalty]) ||
                        get_in(@profile, [:config, :frequency_penalty]) || 0.0
                    }
                    class={[
                      "input input-bordered",
                      Map.has_key?(@form_errors, :frequency_penalty) && "input-error"
                    ]}
                    step="0.1"
                    min="-2"
                    max="2"
                    placeholder="0.0"
                    disabled={@saving}
                  />
                  <label class="label">
                    <span class={[
                      "label-text-alt",
                      Map.has_key?(@form_errors, :frequency_penalty) && "text-error"
                    ]}>
                      {Map.get(
                        @form_errors,
                        :frequency_penalty,
                        "Penalty for repetition (-2.0 to 2.0)"
                      )}
                    </span>
                  </label>
                </div>

                <div class="form-control">
                  <label class="label"><span class="label-text">Seed (Optional)</span></label>
                  <input
                    type="number"
                    name="profile[generation][seed]"
                    value={
                      get_in(@profile, [:generation, :seed]) || get_in(@profile, [:config, :seed]) ||
                        ""
                    }
                    class={[
                      "input input-bordered",
                      Map.has_key?(@form_errors, :seed) && "input-error"
                    ]}
                    placeholder="Random"
                    disabled={@saving}
                  />
                  <label class="label">
                    <span class={["label-text-alt", Map.has_key?(@form_errors, :seed) && "text-error"]}>
                      {Map.get(@form_errors, :seed, "For reproducible outputs")}
                    </span>
                  </label>
                </div>
              </div>
            </div>
          </div>
          <!-- Budget Limits Section -->
          <div class="card bg-base-100 shadow-sm">
            <div class="card-body">
              <h4 class="card-title text-base mb-4">Budget Limits</h4>

              <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                <div class="form-control">
                  <label class="label"><span class="label-text">Max Input Tokens</span></label>
                  <input
                    type="number"
                    name="profile[budgets][max_input_tokens]"
                    value={get_in(@profile, [:budgets, :max_input_tokens]) || ""}
                    class={[
                      "input input-bordered",
                      Map.has_key?(@form_errors, :max_input_tokens) && "input-error"
                    ]}
                    min="1"
                    placeholder="Optional limit"
                    disabled={@saving}
                  />
                  <label class="label">
                    <span class={[
                      "label-text-alt",
                      Map.has_key?(@form_errors, :max_input_tokens) && "text-error"
                    ]}>
                      {Map.get(@form_errors, :max_input_tokens, "Maximum tokens in input")}
                    </span>
                  </label>
                </div>

                <div class="form-control">
                  <label class="label"><span class="label-text">Max Output Tokens</span></label>
                  <input
                    type="number"
                    name="profile[budgets][max_output_tokens]"
                    value={get_in(@profile, [:budgets, :max_output_tokens]) || ""}
                    class={[
                      "input input-bordered",
                      Map.has_key?(@form_errors, :max_output_tokens) && "input-error"
                    ]}
                    min="1"
                    placeholder="Optional limit"
                    disabled={@saving}
                  />
                  <label class="label">
                    <span class={[
                      "label-text-alt",
                      Map.has_key?(@form_errors, :max_output_tokens) && "text-error"
                    ]}>
                      {Map.get(@form_errors, :max_output_tokens, "Maximum tokens in output")}
                    </span>
                  </label>
                </div>

                <div class="form-control">
                  <label class="label"><span class="label-text">Max Total Tokens</span></label>
                  <input
                    type="number"
                    name="profile[budgets][max_total_tokens]"
                    value={get_in(@profile, [:budgets, :max_total_tokens]) || ""}
                    class={[
                      "input input-bordered",
                      Map.has_key?(@form_errors, :max_total_tokens) && "input-error"
                    ]}
                    min="1"
                    placeholder="Optional limit"
                    disabled={@saving}
                  />
                  <label class="label">
                    <span class={[
                      "label-text-alt",
                      Map.has_key?(@form_errors, :max_total_tokens) && "text-error"
                    ]}>
                      {Map.get(@form_errors, :max_total_tokens, "Maximum total tokens per request")}
                    </span>
                  </label>
                </div>

                <div class="form-control">
                  <label class="label"><span class="label-text">Max Cost (EUR)</span></label>
                  <input
                    type="number"
                    name="profile[budgets][max_cost_eur]"
                    value={get_in(@profile, [:budgets, :max_cost_eur]) || ""}
                    class={[
                      "input input-bordered",
                      Map.has_key?(@form_errors, :max_cost_eur) && "input-error"
                    ]}
                    step="0.01"
                    min="0"
                    placeholder="Optional limit"
                    disabled={@saving}
                  />
                  <label class="label">
                    <span class={[
                      "label-text-alt",
                      Map.has_key?(@form_errors, :max_cost_eur) && "text-error"
                    ]}>
                      {Map.get(@form_errors, :max_cost_eur, "Maximum cost per request")}
                    </span>
                  </label>
                </div>

                <div class="form-control">
                  <label class="label"><span class="label-text">Max Steps</span></label>
                  <input
                    type="number"
                    name="profile[budgets][max_steps]"
                    value={get_in(@profile, [:budgets, :max_steps]) || ""}
                    class={[
                      "input input-bordered",
                      Map.has_key?(@form_errors, :max_steps) && "input-error"
                    ]}
                    min="1"
                    placeholder="Optional limit"
                    disabled={@saving}
                  />
                  <label class="label">
                    <span class={[
                      "label-text-alt",
                      Map.has_key?(@form_errors, :max_steps) && "text-error"
                    ]}>
                      {Map.get(@form_errors, :max_steps, "Maximum steps for multi-step operations")}
                    </span>
                  </label>
                </div>
              </div>
            </div>
          </div>
          <!-- Tools and Configuration Section -->
          <div class="card bg-base-100 shadow-sm">
            <div class="card-body">
              <h4 class="card-title text-base mb-4">Tools and Configuration</h4>

              <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div class="form-control">
                  <label class="label"><span class="label-text">Tools (JSON Array)</span></label> <textarea
                    name="profile[tools]"
                    class={[
                      "textarea textarea-bordered font-mono text-sm",
                      Map.has_key?(@form_errors, :tools) && "textarea-error"
                    ]}
                    rows="4"
                    placeholder='["tool1", "tool2", "tool3"]'
                    disabled={@saving}
                  >{format_json_field(@profile.tools)}</textarea>
                  <label class="label">
                    <span class={[
                      "label-text-alt",
                      Map.has_key?(@form_errors, :tools) && "text-error"
                    ]}>
                      {Map.get(@form_errors, :tools, "JSON array of available tool names")}
                    </span>
                  </label>
                </div>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text">Stop Sequences (JSON Array)</span>
                  </label> <textarea
                    name="profile[stop_list]"
                    class={[
                      "textarea textarea-bordered font-mono text-sm",
                      Map.has_key?(@form_errors, :stop_list) && "textarea-error"
                    ]}
                    rows="4"
                    placeholder='["\\n\\n", "END", "STOP"]'
                    disabled={@saving}
                  >{format_json_field(Map.get(@profile, :stop_list, []))}</textarea>
                  <label class="label">
                    <span class={[
                      "label-text-alt",
                      Map.has_key?(@form_errors, :stop_list) && "text-error"
                    ]}>
                      {Map.get(@form_errors, :stop_list, "JSON array of stop sequences")}
                    </span>
                  </label>
                </div>

                <div class="form-control">
                  <label class="label"><span class="label-text">Tags</span></label>
                  <input
                    type="text"
                    name="profile[tags]"
                    value={format_tags_field(@profile.tags)}
                    class={[
                      "input input-bordered",
                      Map.has_key?(@form_errors, :tags) && "input-error"
                    ]}
                    placeholder="production, gpt-4, chat, embeddings"
                    disabled={@saving}
                  />
                  <label class="label">
                    <span class={["label-text-alt", Map.has_key?(@form_errors, :tags) && "text-error"]}>
                      {Map.get(@form_errors, :tags, "Comma-separated tags for categorization")}
                    </span>
                  </label>
                </div>

                <div class="form-control">
                  <label class="label"><span class="label-text">Policy Version</span></label>
                  <input
                    type="text"
                    name="profile[policy_version]"
                    value={Map.get(@profile, :policy_version, "1")}
                    class="input input-bordered"
                    readonly
                    disabled={@saving}
                  />
                  <label class="label">
                    <span class="label-text-alt">Policy version (read-only for now)</span>
                  </label>
                </div>
              </div>
            </div>
          </div>
          <!-- Form Actions with Enhanced UX -->
          <div class="flex gap-2 pt-4 border-t">
            <button
              type="submit"
              class={[
                "btn btn-primary flex-1 sm:flex-none",
                @saving && "loading"
              ]}
              disabled={@saving}
              aria-describedby="save-button-help"
            >
              <.icon :if={!@saving} name="hero-check" class="size-4 mr-2" /> {if @saving do
                if @mode == :create, do: "Creating...", else: "Saving..."
              else
                if @mode == :create, do: "Create Profile", else: "Save Changes"
              end}
            </button>
            <button
              type="button"
              class="btn btn-outline flex-1 sm:flex-none"
              phx-click="back_to_list"
              disabled={@saving}
              aria-label="Cancel and return to list"
            >
              <.icon name="hero-x-mark" class="size-4 mr-2" /> Cancel
            </button>
            <!-- Keyboard shortcuts help -->
            <div class="hidden sm:flex items-center text-xs text-base-content/60 ml-auto">
              <kbd class="kbd kbd-xs">Ctrl</kbd>+<kbd class="kbd kbd-xs">S</kbd> to save,
              <kbd class="kbd kbd-xs">Esc</kbd>
              to cancel
            </div>
          </div>
          <!-- Save button help text -->
          <div id="save-button-help" class="text-xs text-base-content/60 mt-2">
            {if @mode == :create do
              "This will create a new LLM profile that can be used for AI operations."
            else
              "Changes will be applied immediately and affect all future operations using this profile."
            end}
          </div>
        </form>
      </div>
    </div>
    """
  end

  # Helper components
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

  # Helper functions for form data formatting
  defp format_json_field(nil), do: "[]"
  defp format_json_field([]), do: "[]"

  defp format_json_field(list) when is_list(list) do
    Jason.encode!(list, pretty: true)
  rescue
    _ -> "[]"
  end

  defp format_json_field(value) when is_binary(value), do: value
  defp format_json_field(_), do: "[]"

  defp format_tags_field(nil), do: ""
  defp format_tags_field([]), do: ""

  defp format_tags_field(tags) when is_list(tags) do
    tags
    |> Enum.map(&to_string/1)
    |> Enum.join(", ")
  end

  defp format_tags_field(tags) when is_binary(tags), do: tags
  defp format_tags_field(_), do: ""

  # Convert form parameters to context module format with validation
  defp convert_form_params_to_attrs(params) do
    with {:ok, basic_attrs} <- validate_basic_fields(params),
         {:ok, generation_attrs} <- parse_generation_params(params),
         {:ok, budget_attrs} <- parse_budget_params(params),
         {:ok, tools} <- parse_and_validate_json_field(Map.get(params, "tools", "[]"), "tools"),
         {:ok, stop_list} <-
           parse_and_validate_json_field(Map.get(params, "stop_list", "[]"), "stop_list"),
         {:ok, tags} <- parse_and_validate_tags(Map.get(params, "tags", "")) do
      attrs =
        Map.merge(basic_attrs, %{
          tools: tools,
          stop_list: stop_list,
          tags: tags
        })
        |> Map.merge(generation_attrs)
        |> Map.merge(budget_attrs)

      {:ok, attrs}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Validate required basic fields
  defp validate_basic_fields(params) do
    name = String.trim(Map.get(params, "name", ""))
    model = String.trim(Map.get(params, "model", ""))
    provider_id = Map.get(params, "provider_id", "")

    errors = []

    errors = if name == "", do: ["Name is required" | errors], else: errors
    errors = if model == "", do: ["Model is required" | errors], else: errors
    errors = if provider_id == "", do: ["Provider is required" | errors], else: errors

    # Validate provider_id using context module
    errors =
      case Llm.validate_provider_id(provider_id) do
        {:ok, _} -> errors
        {:error, reason} -> [reason | errors]
      end

    if Enum.empty?(errors) do
      {:ok,
       %{
         name: name,
         model: model,
         provider_id: provider_id,
         enabled: parse_boolean(Map.get(params, "enabled", "true")),
         policy_version: Map.get(params, "policy_version", "1"),
         description: Map.get(params, "description", "")
       }}
    else
      {:error, Enum.reverse(errors)}
    end
  end

  # Parse and validate generation parameters
  defp parse_generation_params(params) do
    generation_params = Map.get(params, "generation", %{})

    with {:ok, temperature} <-
           parse_and_validate_float(
             Map.get(generation_params, "temperature"),
             "temperature",
             0.0,
             2.0,
             0.7
           ),
         {:ok, top_p} <-
           parse_and_validate_float(
             Map.get(generation_params, "top_p"),
             "top_p",
             0.0,
             1.0,
             1.0
           ),
         {:ok, max_output_tokens} <-
           parse_and_validate_integer(
             Map.get(generation_params, "max_output_tokens"),
             "max_output_tokens",
             1,
             32000,
             nil
           ),
         {:ok, presence_penalty} <-
           parse_and_validate_float(
             Map.get(generation_params, "presence_penalty"),
             "presence_penalty",
             -2.0,
             2.0,
             0.0
           ),
         {:ok, frequency_penalty} <-
           parse_and_validate_float(
             Map.get(generation_params, "frequency_penalty"),
             "frequency_penalty",
             -2.0,
             2.0,
             0.0
           ) do
      seed = parse_integer(Map.get(generation_params, "seed"))

      {:ok,
       %{
         temperature: temperature,
         top_p: top_p,
         max_output_tokens: max_output_tokens,
         seed: seed,
         presence_penalty: presence_penalty,
         frequency_penalty: frequency_penalty
       }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Parse and validate budget parameters
  defp parse_budget_params(params) do
    budget_params = Map.get(params, "budgets", %{})

    with {:ok, max_input_tokens} <-
           parse_and_validate_integer(
             Map.get(budget_params, "max_input_tokens"),
             "max_input_tokens",
             1,
             nil,
             nil
           ),
         {:ok, max_output_tokens} <-
           parse_and_validate_integer(
             Map.get(budget_params, "max_output_tokens"),
             "max_output_tokens",
             1,
             nil,
             nil
           ),
         {:ok, max_total_tokens} <-
           parse_and_validate_integer(
             Map.get(budget_params, "max_total_tokens"),
             "max_total_tokens",
             1,
             nil,
             nil
           ),
         {:ok, max_cost_eur} <-
           parse_and_validate_float(
             Map.get(budget_params, "max_cost_eur"),
             "max_cost_eur",
             0.0,
             nil,
             nil
           ),
         {:ok, max_steps} <-
           parse_and_validate_integer(
             Map.get(budget_params, "max_steps"),
             "max_steps",
             1,
             nil,
             nil
           ) do
      {:ok,
       %{
         max_input_tokens: max_input_tokens,
         max_output_tokens: max_output_tokens,
         max_total_tokens: max_total_tokens,
         max_cost_eur: max_cost_eur,
         max_steps: max_steps
       }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Parse and validate JSON fields with proper error handling
  defp parse_and_validate_json_field(value, field_name) do
    case parse_json_array(value) do
      list when is_list(list) ->
        # Validate that all items are strings
        if Enum.all?(list, &is_binary/1) do
          {:ok, list}
        else
          {:error, "#{field_name} must contain only string values"}
        end

      _ ->
        {:error, "#{field_name} must be a valid JSON array"}
    end
  end

  # Parse and validate tags
  defp parse_and_validate_tags(value) do
    case parse_tags(value) do
      tags when is_list(tags) ->
        # Validate tag format (alphanumeric, underscore, hyphen only)
        invalid_tags =
          Enum.reject(tags, fn tag ->
            String.match?(tag, ~r/^[a-zA-Z0-9_-]+$/)
          end)

        if Enum.empty?(invalid_tags) do
          {:ok, tags}
        else
          {:error,
           "Invalid tag format: #{Enum.join(invalid_tags, ", ")}. Tags must contain only letters, numbers, underscores, and hyphens."}
        end

      _ ->
        {:error, "Tags must be a comma-separated list"}
    end
  end

  # Parse and validate numeric values with range checking
  defp parse_and_validate_float(value, field_name, min_val, max_val, default) do
    case parse_float(value) do
      nil ->
        {:ok, default}

      float_val when is_float(float_val) ->
        cond do
          min_val && float_val < min_val ->
            {:error, "#{field_name} must be at least #{min_val}"}

          max_val && float_val > max_val ->
            {:error, "#{field_name} must be at most #{max_val}"}

          true ->
            {:ok, float_val}
        end

      _ ->
        {:error, "#{field_name} must be a valid number"}
    end
  end

  defp parse_and_validate_integer(value, field_name, min_val, max_val, default) do
    case parse_integer(value) do
      nil ->
        {:ok, default}

      int_val when is_integer(int_val) ->
        cond do
          min_val && int_val < min_val ->
            {:error, "#{field_name} must be at least #{min_val}"}

          max_val && int_val > max_val ->
            {:error, "#{field_name} must be at most #{max_val}"}

          true ->
            {:ok, int_val}
        end

      _ ->
        {:error, "#{field_name} must be a valid integer"}
    end
  end

  # Format Ecto changeset errors for user display
  defp format_changeset_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {field, errors} ->
      "#{field}: #{Enum.join(errors, ", ")}"
    end)
    |> Enum.join("; ")
  end

  # Helper functions for parsing form values
  defp parse_boolean("true"), do: true
  defp parse_boolean("false"), do: false
  defp parse_boolean(true), do: true
  defp parse_boolean(false), do: false
  defp parse_boolean(_), do: true

  defp parse_float(nil), do: nil
  defp parse_float(""), do: nil
  defp parse_float(value) when is_float(value), do: value

  defp parse_float(value) when is_binary(value) do
    case Float.parse(value) do
      {float_val, _} -> float_val
      :error -> nil
    end
  end

  defp parse_float(_), do: nil

  defp parse_integer(nil), do: nil
  defp parse_integer(""), do: nil
  defp parse_integer(value) when is_integer(value), do: value

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int_val, _} -> int_val
      :error -> nil
    end
  end

  defp parse_integer(_), do: nil

  defp parse_json_array(""), do: []
  defp parse_json_array(nil), do: []
  defp parse_json_array(value) when is_list(value), do: value

  defp parse_json_array(value) when is_binary(value) do
    # Trim whitespace and handle empty/whitespace-only strings
    trimmed = String.trim(value)

    if trimmed == "" do
      []
    else
      case Jason.decode(trimmed) do
        {:ok, list} when is_list(list) -> list
        # Not a list
        {:ok, _} -> :error
        # Invalid JSON
        {:error, _} -> :error
      end
    end
  end

  defp parse_json_array(_), do: :error

  defp parse_tags(""), do: []
  defp parse_tags(nil), do: []
  defp parse_tags(value) when is_list(value), do: value

  defp parse_tags(value) when is_binary(value) do
    value
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_tags(_), do: []

  attr :provider, :string, required: true

  defp provider_badge(assigns) do
    {badge_class, icon} =
      case String.downcase(assigns.provider) do
        "openai" -> {"badge-primary", "hero-bolt"}
        "openai_compatible" -> {"badge-primary", "hero-bolt"}
        "anthropic" -> {"badge-secondary", "hero-academic-cap"}
        "google" -> {"badge-accent", "hero-sparkles"}
        "azure" -> {"badge-info", "hero-cloud"}
        "local" -> {"badge-warning", "hero-server"}
        "fake" -> {"badge-warning", "hero-beaker"}
        "cohere" -> {"badge-secondary", "hero-chat-bubble-left-right"}
        "mistral" -> {"badge-accent", "hero-fire"}
        "together" -> {"badge-info", "hero-users"}
        "huggingface" -> {"badge-primary", "hero-face-smile"}
        "replicate" -> {"badge-secondary", "hero-arrow-path"}
        _ -> {"badge-ghost", "hero-question-mark-circle"}
      end

    assigns = assign(assigns, :badge_class, badge_class)
    assigns = assign(assigns, :icon, icon)

    ~H"""
    <div class={["badge badge-sm gap-1", @badge_class]}>
      <.icon name={@icon} class="size-3" /> {String.capitalize(@provider)}
    </div>
    """
  end

  attr :status, :string, required: true

  defp status_badge(assigns) do
    {badge_class, icon} =
      case assigns.status do
        "active" -> {"badge-success", "hero-check-circle"}
        "inactive" -> {"badge-error", "hero-x-circle"}
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

  attr :provider, :string, required: true
  attr :available_providers, :list, required: true

  defp provider_config_hints(assigns) do
    provider_info = Enum.find(assigns.available_providers, &(&1.value == assigns.provider))
    assigns = assign(assigns, :provider_info, provider_info)

    ~H"""
    <div :if={@provider_info} class="space-y-4">
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <!-- API Configuration -->
        <div class="space-y-2">
          <h5 class="font-medium text-sm">API Configuration</h5>

          <div class="text-sm space-y-1">
            <div class="flex items-center gap-2">
              <.icon
                name={
                  if @provider_info.configuration_hints.api_key_required,
                    do: "hero-key",
                    else: "hero-lock-open"
                }
                class="size-4"
              />
              <span class={
                if @provider_info.configuration_hints.api_key_required,
                  do: "text-warning",
                  else: "text-success"
              }>
                {if @provider_info.configuration_hints.api_key_required,
                  do: "API Key Required",
                  else: "No API Key Required"}
              </span>
            </div>

            <div class="flex items-center gap-2">
              <.icon name="hero-globe-alt" class="size-4" />
              <span class="text-base-content/70">
                Base URL: {@provider_info.configuration_hints.base_url}
              </span>
            </div>

            <div
              :if={Map.has_key?(@provider_info.configuration_hints, :additional_config)}
              class="flex items-center gap-2"
            >
              <.icon name="hero-cog-6-tooth" class="size-4" />
              <span class="text-base-content/70">
                Additional Config: {Enum.join(
                  @provider_info.configuration_hints.additional_config,
                  ", "
                )}
              </span>
            </div>
          </div>
        </div>
        <!-- Model Information -->
        <div class="space-y-2">
          <h5 class="font-medium text-sm">Model Information</h5>

          <div class="text-sm space-y-1">
            <div class="flex items-center gap-2">
              <.icon name="hero-cpu-chip" class="size-4" />
              <span class="text-base-content/70">
                Max Tokens: {@provider_info.configuration_hints.max_tokens_limit}
              </span>
            </div>

            <div class="flex items-center gap-2">
              <.icon
                name={
                  if @provider_info.configuration_hints.supports_streaming,
                    do: "hero-signal",
                    else: "hero-signal-slash"
                }
                class="size-4"
              />
              <span class={
                if @provider_info.configuration_hints.supports_streaming,
                  do: "text-success",
                  else: "text-warning"
              }>
                {if @provider_info.configuration_hints.supports_streaming,
                  do: "Streaming Supported",
                  else: "No Streaming"}
              </span>
            </div>
          </div>
        </div>
      </div>
      <!-- Supported Features -->
      <div class="space-y-2">
        <h5 class="font-medium text-sm">Supported Features</h5>

        <div class="flex flex-wrap gap-2">
          <div
            :for={feature <- @provider_info.supported_features}
            class="badge badge-outline badge-sm"
          >
            {String.capitalize(to_string(feature))}
          </div>
        </div>
      </div>
      <!-- Common Models -->
      <div :if={length(@provider_info.configuration_hints.common_models) > 0} class="space-y-2">
        <h5 class="font-medium text-sm">Common Models</h5>

        <div class="text-sm text-base-content/70">
          <div class="flex flex-wrap gap-1">
            <code
              :for={model <- @provider_info.configuration_hints.common_models}
              class="bg-base-200 px-2 py-1 rounded text-xs"
            >
              {model}
            </code>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
