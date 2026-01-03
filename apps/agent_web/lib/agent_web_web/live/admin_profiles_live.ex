defmodule AgentWebWeb.AdminProfilesLive do
  @moduledoc """
  Admin profiles management LiveView for LLM profile management.
  Provides interface for LLM profile CRUD operations, model configuration, and performance tracking.
  """
  use AgentWebWeb, :live_view
  require AgentWebWeb.AdminErrorHandler
  alias AgentWebWeb.{AdminLayouts, AdminErrorHandler}
  alias AgentCore.Llm.Profiles

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

  # 3. Handler για το μήνυμα από το LiveComponent
  #    Αυτό είναι το ΚΡΙΣΙΜΟ κομμάτι!
  @impl true
  def handle_info({:toggle_sidebar}, socket) do
    new_state = !socket.assigns.sidebar_collapsed
    {:noreply, assign(socket, :sidebar_collapsed, new_state)}
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

    {:noreply,
     socket
     |> assign(:selected_profile, profile)
     |> assign(:view_mode, :edit)}
  end

  @impl true
  def handle_event("create_profile", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_profile, get_empty_profile())
     |> assign(:view_mode, :create)}
  end

  @impl true
  def handle_event("back_to_list", _params, socket) do
    {:noreply,
     socket
     |> assign(:view_mode, :list)
     |> assign(:selected_profile, nil)}
  end

  @impl true
  def handle_event("save_profile", %{"profile" => _profile_params}, socket) do
    # TODO: Implement profile saving
    {:noreply,
     socket
     |> assign(:view_mode, :list)
     |> assign(:selected_profile, nil)
     |> put_flash(:info, "Profile saved successfully")
     |> load_profiles_data()}
  end

  @impl true
  def handle_event("delete_profile", %{"profile_id" => _profile_id}, socket) do
    # TODO: Implement profile deletion
    {:noreply,
     socket
     |> put_flash(:info, "Profile deleted successfully")
     |> load_profiles_data()}
  end

  @impl true
  def handle_event("toggle_status", %{"profile_id" => _profile_id}, socket) do
    # TODO: Implement status toggle
    {:noreply,
     socket
     |> put_flash(:info, "Profile status updated")
     |> load_profiles_data()}
  end

  @impl true
  def handle_event("bulk_action", %{"action" => action, "selected" => selected}, socket) do
    # TODO: Implement bulk actions
    count = length(selected)

    message =
      case action do
        "activate" -> "#{count} profiles activated"
        "deactivate" -> "#{count} profiles deactivated"
        "delete" -> "#{count} profiles deleted"
        _ -> "Bulk action completed"
      end

    {:noreply,
     socket
     |> put_flash(:info, message)
     |> load_profiles_data()}
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

      <div :if={@view_mode == :list}>
        <.profiles_list
          profiles={@filtered_profiles}
          search_query={@search_query}
          provider_filter={@provider_filter}
          status_filter={@status_filter}
          profile_stats={@profile_stats}
        />
      </div>

      <div :if={@view_mode == :detail && @selected_profile}>
        <.profile_detail profile={@selected_profile} />
      </div>

      <div :if={@view_mode in [:edit, :create] && @selected_profile}>
        <.profile_form
          profile={@selected_profile}
          mode={@view_mode}
          available_providers={@available_providers}
        />
      </div>
    </AdminLayouts.admin>
    """
  end

  # Load profiles data
  defp load_profiles_data(socket) do
    AdminErrorHandler.handle_data_loading(socket, :profiles, fn ->
      # Load actual profiles from database
      all_profiles =
        Profiles.list()
        |> Enum.map(&convert_llm_profile_to_ui_format/1)

      profile_stats = calculate_profile_stats(all_profiles)
      available_providers = get_available_providers()

      %{
        all_profiles: all_profiles,
        profile_stats: profile_stats,
        available_providers: available_providers
      }
    end)
    |> case do
      %{
        profiles: %{
          all_profiles: all_profiles,
          profile_stats: profile_stats,
          available_providers: available_providers
        }
      } ->
        socket
        |> assign(:all_profiles, all_profiles)
        |> assign(:profile_stats, profile_stats)
        |> assign(:available_providers, available_providers)
        |> filter_profiles()

      socket ->
        # Error case - use fallback data
        socket
        |> assign(:all_profiles, [])
        |> assign(:profile_stats, %{
          total: 0,
          active: 0,
          inactive: 0,
          openai: 0,
          anthropic: 0,
          google: 0
        })
        |> assign(:available_providers, ["openai", "anthropic", "google"])
        |> filter_profiles()
    end
  end

  defp filter_profiles(socket) do
    profiles = socket.assigns.all_profiles
    search = String.downcase(socket.assigns.search_query)
    provider_filter = socket.assigns.provider_filter
    status_filter = socket.assigns.status_filter

    filtered =
      profiles
      |> Enum.filter(fn profile ->
        search_match =
          search == "" or
            String.contains?(String.downcase(profile.name), search) or
            String.contains?(String.downcase(profile.model), search)

        provider_match = provider_filter == "all" or profile.provider == provider_filter
        status_match = status_filter == "all" or profile.status == status_filter

        search_match and provider_match and status_match
      end)

    assign(socket, :filtered_profiles, filtered)
  end

  # Convert LLMProfile domain struct to UI format
  defp convert_llm_profile_to_ui_format(%AgentCore.Llm.LLMProfile{} = profile) do
    %{
      id: profile.id,
      name: profile.name,
      provider: to_string(profile.provider),
      model: profile.model,
      status: if(profile.enabled, do: "active", else: "inactive"),
      enabled: profile.enabled,
      temperature: profile.generation.temperature,
      max_tokens: profile.generation.max_output_tokens,
      tools: profile.tools,
      tags: profile.tags,
      created_at: format_datetime(profile.inserted_at),
      updated_at: format_datetime(profile.updated_at),
      # TODO: Get from actual usage tracking
      last_used: "Never",
      # TODO: Get from actual usage tracking
      usage_count: 0,
      config: %{
        temperature: profile.generation.temperature,
        max_tokens: profile.generation.max_output_tokens,
        # Default value since not in domain model
        top_p: 1.0,
        # Default value since not in domain model
        frequency_penalty: 0.0,
        # Default value since not in domain model
        presence_penalty: 0.0
      },
      cost_per_1k_tokens: %{
        # TODO: Get from provider configuration
        input: 0.0,
        # TODO: Get from provider configuration
        output: 0.0
      },
      # TODO: Add description field to domain model
      description: "",
      usage_stats: %{
        # TODO: Get from actual usage tracking
        total_requests: 0,
        total_tokens: 0,
        avg_response_time: 0,
        success_rate: 100.0
      }
    }
  end

  # Helper function to format datetime
  defp format_datetime(nil), do: "Never"

  defp format_datetime(datetime) do
    case DateTime.from_naive(datetime, "Etc/UTC") do
      {:ok, dt} -> Calendar.strftime(dt, "%Y-%m-%d")
      _ -> "Unknown"
    end
  end

  # Mock data functions

  defp calculate_profile_stats(profiles) do
    %{
      total: length(profiles),
      active: Enum.count(profiles, &(&1.status == "active")),
      inactive: Enum.count(profiles, &(&1.status == "inactive")),
      openai: Enum.count(profiles, &(&1.provider == "openai")),
      anthropic: Enum.count(profiles, &(&1.provider == "anthropic")),
      google: Enum.count(profiles, &(&1.provider == "google"))
    }
  end

  defp get_available_providers do
    [
      %{value: "openai", label: "OpenAI", description: "GPT models from OpenAI"},
      %{value: "anthropic", label: "Anthropic", description: "Claude models from Anthropic"},
      %{value: "google", label: "Google", description: "Gemini models from Google"},
      %{value: "azure", label: "Azure OpenAI", description: "OpenAI models via Azure"},
      %{value: "local", label: "Local", description: "Self-hosted models"}
    ]
  end

  defp get_empty_profile do
    %{
      id: nil,
      name: "",
      model: "",
      provider: "openai",
      status: "active",
      enabled: true,
      temperature: 0.7,
      max_tokens: 2048,
      tools: [],
      tags: [],
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
        presence_penalty: 0.0
      },
      cost_per_1k_tokens: %{
        input: 0.0,
        output: 0.0
      },
      description: ""
    }
  end

  # Components
  attr :profiles, :list, required: true
  attr :search_query, :string, required: true
  attr :provider_filter, :string, required: true
  attr :status_filter, :string, required: true
  attr :profile_stats, :map, required: true

  defp profiles_list(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Profile Statistics -->
      <div class="grid grid-cols-2 md:grid-cols-6 gap-4">
        <.stat_card title="Total" value={@profile_stats.total} color="primary" />
        <.stat_card title="Active" value={@profile_stats.active} color="success" />
        <.stat_card title="Inactive" value={@profile_stats.inactive} color="warning" />
        <.stat_card title="OpenAI" value={@profile_stats.openai} color="info" />
        <.stat_card title="Anthropic" value={@profile_stats.anthropic} color="secondary" />
        <.stat_card title="Google" value={@profile_stats.google} color="accent" />
      </div>
      <!-- Filters and Search -->
      <div class="card bg-base-200 shadow-sm">
        <div class="card-body">
          <div class="flex flex-wrap gap-4">
            <div class="form-control">
              <input
                type="text"
                placeholder="Search profiles..."
                class="input input-bordered input-sm w-64"
                value={@search_query}
                phx-change="search_profiles"
                phx-value-search={@search_query}
              />
            </div>

            <div class="form-control">
              <select
                class="select select-bordered select-sm"
                phx-change="filter_by_provider"
              >
                <option value="all" selected={@provider_filter == "all"}>All Providers</option>

                <option value="openai" selected={@provider_filter == "openai"}>OpenAI</option>

                <option value="anthropic" selected={@provider_filter == "anthropic"}>
                  Anthropic
                </option>

                <option value="google" selected={@provider_filter == "google"}>Google</option>

                <option value="azure" selected={@provider_filter == "azure"}>Azure</option>

                <option value="local" selected={@provider_filter == "local"}>Local</option>
              </select>
            </div>

            <div class="form-control">
              <select
                class="select select-bordered select-sm"
                phx-change="filter_by_status"
              >
                <option value="all" selected={@status_filter == "all"}>All Status</option>

                <option value="active" selected={@status_filter == "active"}>Active</option>

                <option value="inactive" selected={@status_filter == "inactive"}>Inactive</option>
              </select>
            </div>
          </div>
        </div>
      </div>
      <!-- Profiles Table -->
      <div class="card bg-base-200 shadow-sm">
        <div class="card-body">
          <div class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th><input type="checkbox" class="checkbox checkbox-sm" /></th>

                  <th>Profile</th>

                  <th>Provider</th>

                  <th>Status</th>

                  <th>Usage</th>

                  <th>Last Used</th>

                  <th>Actions</th>
                </tr>
              </thead>

              <tbody>
                <tr :for={profile <- @profiles}>
                  <td><input type="checkbox" class="checkbox checkbox-sm" /></td>

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
                        class="btn btn-error btn-xs"
                        phx-click="delete_profile"
                        phx-value-profile_id={profile.id}
                        title="Delete Profile"
                      >
                        <.icon name="hero-trash" class="size-3" />
                      </button>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
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

  defp profile_form(assigns) do
    ~H"""
    <div class="card bg-base-200 shadow-sm max-w-2xl mx-auto">
      <div class="card-body">
        <h3 class="card-title text-lg">
          {if @mode == :create, do: "Create New Profile", else: "Edit Profile"}
        </h3>

        <form phx-submit="save_profile" class="space-y-4">
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div class="form-control">
              <label class="label"><span class="label-text">Name</span></label>
              <input
                type="text"
                name="profile[name]"
                value={@profile.name}
                class="input input-bordered"
                required
              />
            </div>

            <div class="form-control">
              <label class="label"><span class="label-text">Model</span></label>
              <input
                type="text"
                name="profile[model]"
                value={@profile.model}
                class="input input-bordered"
                required
              />
            </div>

            <div class="form-control">
              <label class="label"><span class="label-text">Provider</span></label>
              <select name="profile[provider]" class="select select-bordered">
                <option
                  :for={provider <- @available_providers}
                  value={provider.value}
                  selected={provider.value == @profile.provider}
                >
                  {provider.label}
                </option>
              </select>
            </div>

            <div class="form-control">
              <label class="label"><span class="label-text">Status</span></label>
              <select name="profile[status]" class="select select-bordered">
                <option value="active" selected={@profile.status == "active"}>Active</option>
                <option value="inactive" selected={@profile.status == "inactive"}>Inactive</option>
              </select>
            </div>

            <div class="form-control">
              <label class="label"><span class="label-text">Temperature</span></label>
              <input
                type="number"
                name="profile[temperature]"
                value={@profile.config.temperature}
                class="input input-bordered"
                step="0.1"
                min="0"
                max="2"
              />
            </div>

            <div class="form-control">
              <label class="label"><span class="label-text">Max Tokens</span></label>
              <input
                type="number"
                name="profile[max_tokens]"
                value={@profile.config.max_tokens}
                class="input input-bordered"
                min="1"
                max="32000"
              />
            </div>
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text">Description</span></label>
            <textarea
              name="profile[description]"
              class="textarea textarea-bordered"
              rows="3"
            >{@profile.description}</textarea>
          </div>

          <div class="flex gap-2 pt-4">
            <button type="submit" class="btn btn-primary">
              <.icon name="hero-check" class="size-4 mr-2" /> {if @mode == :create,
                do: "Create Profile",
                else: "Save Changes"}
            </button>
            <button
              type="button"
              class="btn btn-outline"
              phx-click="back_to_list"
            >
              Cancel
            </button>
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

  attr :provider, :string, required: true

  defp provider_badge(assigns) do
    {badge_class, icon} =
      case assigns.provider do
        "openai" -> {"badge-primary", "hero-bolt"}
        "anthropic" -> {"badge-secondary", "hero-academic-cap"}
        "google" -> {"badge-accent", "hero-sparkles"}
        "azure" -> {"badge-info", "hero-cloud"}
        "local" -> {"badge-warning", "hero-server"}
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
end
