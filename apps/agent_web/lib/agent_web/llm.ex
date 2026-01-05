defmodule AgentWeb.Llm do
  @moduledoc """
  Web boundary context for LLM read models.

  Purpose:
  - Provide a stable boundary for AgentWeb (LiveViews, Controllers).
  - Keep UI/read-model mapping out of domain modules.
  - Support future non-Elixir consumers via controllers without coupling UI to AgentCore.
  """

  alias AgentCore.Llm.{Profiles, LLMProfile, GenerationParams, Budgets}

  @type filters :: %{
          optional(:q) => String.t(),
          optional(:provider) => String.t(),
          optional(:status) => String.t()
        }

  @type ui_profile :: map()

  @spec list_profiles_ui(filters()) :: {:ok, list(ui_profile())} | {:error, String.t()}
  def list_profiles_ui(filters \\ %{}) when is_map(filters) do
    try do
      profiles =
        filters
        |> list_opts_from_filters()
        |> Profiles.list()
        |> Enum.map(&to_ui_profile/1)
        |> apply_in_memory_filters(filters)

      {:ok, profiles}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  @spec calculate_profile_stats(list(ui_profile())) :: map()
  def calculate_profile_stats(ui_profiles) when is_list(ui_profiles) do
    # Get all unique providers from the profiles
    provider_counts =
      ui_profiles
      |> Enum.group_by(& &1.provider)
      |> Enum.map(fn {provider, profiles} -> {String.to_atom(provider), length(profiles)} end)
      |> Enum.into(%{})

    # Base stats
    base_stats = %{
      total: length(ui_profiles),
      active: Enum.count(ui_profiles, &(&1.status == "active")),
      inactive: Enum.count(ui_profiles, &(&1.status == "inactive"))
    }

    # Get all available provider types from database
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

    # Create stats for all available provider types
    provider_stats =
      available_provider_types
      |> Enum.map(fn provider -> {provider, Map.get(provider_counts, provider, 0)} end)
      |> Enum.into(%{})

    Map.merge(base_stats, provider_stats)
  end

  @doc """
  Get provider configuration hints for a specific provider.
  """
  @spec get_provider_config(String.t() | atom()) :: {:ok, map()} | {:error, String.t()}
  def get_provider_config(provider) when is_binary(provider) do
    case find_provider_by_value(provider) do
      nil -> {:error, "Provider '#{provider}' not found"}
      provider_info -> {:ok, provider_info.configuration_hints}
    end
  end

  def get_provider_config(provider) when is_atom(provider) do
    get_provider_config(Atom.to_string(provider))
  end

  @doc """
  Validate if a provider is supported.
  """
  @spec validate_provider(String.t() | atom()) :: {:ok, atom()} | {:error, String.t()}
  def validate_provider(provider) when is_binary(provider) do
    supported_providers = get_supported_provider_values()

    if provider in supported_providers do
      {:ok, String.to_atom(provider)}
    else
      {:error,
       "Provider '#{provider}' is not supported. Supported providers: #{Enum.join(supported_providers, ", ")}"}
    end
  end

  def validate_provider(provider) when is_atom(provider) do
    validate_provider(Atom.to_string(provider))
  end

  @doc """
  Validate if a provider_id references an existing provider in the database.
  """
  @spec validate_provider_id(String.t() | integer()) :: {:ok, String.t()} | {:error, String.t()}
  def validate_provider_id(provider_id) when is_binary(provider_id) or is_integer(provider_id) do
    case AgentWeb.Providers.get_provider(provider_id) do
      {:ok, provider} ->
        if provider.enabled do
          {:ok, to_string(provider_id)}
        else
          {:error, "Provider '#{provider.name}' is disabled"}
        end
      {:error, :not_found} ->
        {:error, "Provider with ID '#{provider_id}' not found"}
      {:error, reason} ->
        {:error, "Failed to validate provider: #{reason}"}
    end
  end

  @doc """
  Get list of supported provider values (strings).
  """
  @spec get_supported_provider_values() :: [String.t()]
  def get_supported_provider_values do
    Enum.map(available_providers(), & &1.value)
  end

  @doc """
  Get list of supported provider atoms.
  """
  @spec get_supported_provider_atoms() :: [atom()]
  def get_supported_provider_atoms do
    Enum.map(available_providers(), &String.to_atom(&1.value))
  end

  @doc """
  Find provider information by value.
  """
  @spec find_provider_by_value(String.t()) :: map() | nil
  def find_provider_by_value(value) when is_binary(value) do
    Enum.find(available_providers(), &(&1.value == value))
  end

  @doc """
  Convert provider string to atom safely.
  """
  @spec convert_provider_to_atom(String.t()) :: {:ok, atom()} | {:error, String.t()}
  def convert_provider_to_atom(provider) when is_binary(provider) do
    case validate_provider(provider) do
      {:ok, atom} -> {:ok, atom}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Get provider-specific model suggestions.
  """
  @spec get_provider_model_suggestions(String.t() | atom()) ::
          {:ok, [String.t()]} | {:error, String.t()}
  def get_provider_model_suggestions(provider) do
    case get_provider_config(provider) do
      {:ok, config} -> {:ok, Map.get(config, :common_models, [])}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Check if provider supports a specific feature.
  """
  @spec provider_supports_feature?(String.t() | atom(), atom()) :: boolean()
  def provider_supports_feature?(provider, feature) when is_atom(feature) do
    case find_provider_by_value(to_string(provider)) do
      nil ->
        false

      provider_info ->
        supported_features = Map.get(provider_info, :supported_features, [])
        feature in supported_features
    end
  end

  def available_providers do
    # Load providers from database instead of hardcoded list
    case AgentWeb.Providers.list_providers_for_profiles() do
      {:ok, providers} ->
        providers
        |> Enum.map(fn provider ->
          %{
            value: provider.id,
            label: provider.name,
            description: provider.description || "#{provider.name} provider",
            type: provider.type,
            enabled: provider.enabled,
            supported_models: provider.supported_models || [],
            configuration_hints: %{
              base_url: provider.base_url,
              auth_type: provider.auth_type,
              supports_streaming: true  # Default assumption
            }
          }
        end)
        |> Enum.filter(& &1.enabled)  # Only show enabled providers

      {:error, _reason} ->
        # Fallback to empty list if database is unavailable
        []
    end
  end

  @doc """
  Create a new LLM profile.
  """
  @spec create_profile(map()) :: {:ok, LLMProfile.t()} | {:error, String.t()}
  def create_profile(attrs) when is_map(attrs) do
    with {:ok, validated_attrs} <- validate_profile_attrs(attrs),
         profile <- build_llm_profile(validated_attrs),
         {:ok, _id} <- Profiles.put(profile) do
      {:ok, profile}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Update an existing LLM profile.
  """
  @spec update_profile(String.t(), map()) :: {:ok, LLMProfile.t()} | {:error, String.t()}
  def update_profile(id, attrs) when is_binary(id) and is_map(attrs) do
    with {:ok, existing} <- Profiles.get(id),
         {:ok, validated_attrs} <- validate_profile_attrs(attrs),
         updated_profile <- update_llm_profile(existing, validated_attrs),
         {:ok, _id} <- Profiles.put(updated_profile) do
      {:ok, updated_profile}
    else
      :error -> {:error, "Profile not found"}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Delete an LLM profile by ID.
  """
  @spec delete_profile(String.t()) :: :ok | {:error, String.t()}
  def delete_profile(id) when is_binary(id) do
    # First check if profile exists
    case Profiles.get(id) do
      {:ok, _profile} ->
        # Profile exists, proceed with deletion
        case get_store().delete(id) do
          :ok ->
            :ok

          {:error, :not_found} ->
            {:error, "Profile not found"}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:error, "Failed to delete profile: #{format_changeset_errors(changeset)}"}

          {:error, reason} ->
            {:error, "Failed to delete profile: #{inspect(reason)}"}
        end

      :error ->
        {:error, "Profile not found"}
    end
  end

  @doc """
  Toggle the enabled status of an LLM profile.
  """
  @spec toggle_profile_status(String.t()) :: {:ok, LLMProfile.t()} | {:error, String.t()}
  def toggle_profile_status(id) when is_binary(id) do
    with {:ok, existing} <- Profiles.get(id),
         updated_profile <- %{existing | enabled: !existing.enabled},
         {:ok, _id} <- Profiles.put(updated_profile) do
      {:ok, updated_profile}
    else
      :error -> {:error, "Profile not found"}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Perform bulk actions on multiple profiles.
  """
  @spec bulk_action(String.t(), [String.t()]) :: {:ok, map()} | {:error, String.t()}
  def bulk_action(action, profile_ids) when is_binary(action) and is_list(profile_ids) do
    case action do
      "activate" -> bulk_toggle_status(profile_ids, true)
      "deactivate" -> bulk_toggle_status(profile_ids, false)
      "delete" -> bulk_delete(profile_ids)
      _ -> {:error, "Unknown bulk action: #{action}"}
    end
  end

  # -----------------------------
  # Internal helpers
  # -----------------------------

  # Get the configured store module
  defp get_store do
    Application.fetch_env!(:agent_core, AgentCore.Llm.Profiles)
    |> Keyword.fetch!(:store)
  end

  # Bulk operations helpers

  defp bulk_toggle_status(profile_ids, enabled)
       when is_list(profile_ids) and is_boolean(enabled) do
    results =
      Enum.map(profile_ids, fn id ->
        case Profiles.get(id) do
          {:ok, profile} ->
            updated_profile = %{profile | enabled: enabled}

            case Profiles.put(updated_profile) do
              {:ok, _id} -> {:ok, id}
              {:error, reason} -> {:error, {id, reason}}
            end

          :error ->
            {:error, {id, "Profile not found"}}
        end
      end)

    {successes, failures} =
      Enum.split_with(results, fn
        {:ok, _} -> true
        {:error, _} -> false
      end)

    success_count = length(successes)
    failure_count = length(failures)

    if failure_count == 0 do
      action_name = if enabled, do: "activated", else: "deactivated"

      {:ok,
       %{
         success_count: success_count,
         failure_count: 0,
         message: "#{success_count} profiles #{action_name} successfully"
       }}
    else
      action_name = if enabled, do: "activate", else: "deactivate"
      failure_details = Enum.map(failures, fn {:error, {id, reason}} -> "#{id}: #{reason}" end)

      {:error,
       "Failed to #{action_name} #{failure_count} profiles: #{Enum.join(failure_details, "; ")}"}
    end
  end

  defp bulk_delete(profile_ids) when is_list(profile_ids) do
    results =
      Enum.map(profile_ids, fn id ->
        case delete_profile(id) do
          :ok -> {:ok, id}
          {:error, reason} -> {:error, {id, reason}}
        end
      end)

    {successes, failures} =
      Enum.split_with(results, fn
        {:ok, _} -> true
        {:error, _} -> false
      end)

    success_count = length(successes)
    failure_count = length(failures)

    if failure_count == 0 do
      {:ok,
       %{
         success_count: success_count,
         failure_count: 0,
         message: "#{success_count} profiles deleted successfully"
       }}
    else
      failure_details = Enum.map(failures, fn {:error, {id, reason}} -> "#{id}: #{reason}" end)
      {:error, "Failed to delete #{failure_count} profiles: #{Enum.join(failure_details, "; ")}"}
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

  # Profile creation and validation helpers

  defp validate_profile_attrs(attrs) do
    required_fields = [:name, :model, :provider_id]

    missing_fields =
      Enum.reject(required_fields, &Map.has_key?(attrs, &1))

    if Enum.empty?(missing_fields) do
      # Validate provider_id specifically
      case validate_provider_id(attrs[:provider_id]) do
        {:ok, _provider_id} -> {:ok, attrs}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, "Missing required fields: #{inspect(missing_fields)}"}
    end
  end

  defp build_llm_profile(attrs) do
    %LLMProfile{
      id: attrs[:id] || generate_profile_id(),
      name: attrs[:name],
      model: attrs[:model],
      provider_id: attrs[:provider_id],
      enabled: Map.get(attrs, :enabled, true),
      policy_version: Map.get(attrs, :policy_version, "1"),
      generation: build_generation_params(attrs),
      budgets: build_budgets(attrs),
      tools: Map.get(attrs, :tools, []),
      stop_list: Map.get(attrs, :stop_list, []),
      tags: generate_tags(attrs),
      inserted_at: nil,
      updated_at: nil
    }
  end

  defp update_llm_profile(%LLMProfile{} = existing, attrs) do
    %LLMProfile{
      existing
      | name: Map.get(attrs, :name, existing.name),
        model: Map.get(attrs, :model, existing.model),
        provider_id: Map.get(attrs, :provider_id, existing.provider_id),
        enabled: Map.get(attrs, :enabled, existing.enabled),
        policy_version: Map.get(attrs, :policy_version, existing.policy_version),
        generation: build_generation_params(attrs, existing.generation),
        budgets: build_budgets(attrs, existing.budgets),
        tools: Map.get(attrs, :tools, existing.tools),
        stop_list: Map.get(attrs, :stop_list, existing.stop_list),
        tags: generate_tags(attrs, existing.tags)
    }
  end

  defp generate_profile_id do
    # Generate a UUID for new profiles
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
    |> String.slice(0, 8)
  end



  defp generate_tags(attrs, existing_tags \\ []) do
    auto_tags = generate_auto_tags(attrs)
    manual_tags = parse_manual_tags(Map.get(attrs, :tags, []))

    # Combine auto, manual, and existing tags, removing duplicates
    all_tags =
      (auto_tags ++ manual_tags ++ existing_tags)
      |> Enum.uniq()
      |> Enum.reject(&is_nil/1)

    all_tags
  end

  defp generate_auto_tags(attrs) do
    tags = []

    # Add provider tag based on provider_id
    provider_tag =
      case Map.get(attrs, :provider_id) do
        provider_id when is_binary(provider_id) or is_integer(provider_id) ->
          # Get provider info from database to generate meaningful tag
          case AgentWeb.Providers.get_provider(provider_id) do
            {:ok, provider} -> String.to_atom(provider.type)
            {:error, _} -> nil
          end
        _ -> nil
      end

    tags = if provider_tag, do: [provider_tag | tags], else: tags

    # Add model-based tags
    model = Map.get(attrs, :model, "")

    # Model name tag (e.g., gpt-4 -> :gpt4)
    model_tag =
      model
      |> String.replace("-", "_")
      |> String.replace(".", "_")
      |> String.downcase()
      |> case do
        "" -> nil
        clean_model -> String.to_atom(clean_model)
      end

    tags = if model_tag, do: [model_tag | tags], else: tags

    # Feature-based tags
    model_lower = String.downcase(model)

    tags = if String.contains?(model_lower, "embed"), do: [:embeddings | tags], else: tags
    tags = if String.contains?(model_lower, "chat"), do: [:chat | tags], else: tags
    tags = if String.contains?(model_lower, "vision"), do: [:vision | tags], else: tags
    tags = if String.contains?(model_lower, "gpt"), do: [:gpt | tags], else: tags
    tags = if String.contains?(model_lower, "claude"), do: [:claude | tags], else: tags

    tags
  end

  defp parse_manual_tags(tags) when is_list(tags) do
    Enum.map(tags, fn
      tag when is_atom(tag) -> tag
      tag when is_binary(tag) -> String.to_atom(tag)
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_manual_tags(tags) when is_binary(tags) do
    tags
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&String.to_atom/1)
  end

  defp parse_manual_tags(_), do: []

  defp build_generation_params(attrs, existing \\ %GenerationParams{}) do
    %GenerationParams{
      temperature: get_float_attr(attrs, :temperature, existing.temperature, 0.7),
      top_p: get_float_attr(attrs, :top_p, existing.top_p, 1.0),
      max_output_tokens: get_integer_attr(attrs, :max_output_tokens, existing.max_output_tokens),
      seed: get_integer_attr(attrs, :seed, existing.seed),
      presence_penalty: get_float_attr(attrs, :presence_penalty, existing.presence_penalty, 0.0),
      frequency_penalty:
        get_float_attr(attrs, :frequency_penalty, existing.frequency_penalty, 0.0),
      stop: Map.get(attrs, :stop, existing.stop)
    }
  end

  defp build_budgets(attrs, existing \\ %Budgets{}) do
    %Budgets{
      max_input_tokens: get_integer_attr(attrs, :max_input_tokens, existing.max_input_tokens),
      max_output_tokens: get_integer_attr(attrs, :max_output_tokens, existing.max_output_tokens),
      max_total_tokens: get_integer_attr(attrs, :max_total_tokens, existing.max_total_tokens),
      max_cost_eur: get_float_attr(attrs, :max_cost_eur, existing.max_cost_eur),
      max_steps: get_integer_attr(attrs, :max_steps, existing.max_steps)
    }
  end

  defp get_float_attr(attrs, key, existing_value, default \\ nil) do
    case Map.get(attrs, key) do
      nil ->
        existing_value || default

      value when is_float(value) ->
        value

      value when is_binary(value) ->
        case Float.parse(value) do
          {float_val, _} -> float_val
          :error -> existing_value || default
        end

      _ ->
        existing_value || default
    end
  end

  defp get_integer_attr(attrs, key, existing_value, default \\ nil) do
    case Map.get(attrs, key) do
      nil ->
        existing_value || default

      value when is_integer(value) ->
        value

      value when is_binary(value) ->
        case Integer.parse(value) do
          {int_val, _} -> int_val
          :error -> existing_value || default
        end

      _ ->
        existing_value || default
    end
  end

  # Build opts for Profiles.list/1 based on filters.
  # We intentionally keep this minimal because we don't know all supported opts of Profiles.list/1.
  # We DO apply the UI filters reliably in-memory afterwards.
  defp list_opts_from_filters(filters) do
    []
    |> maybe_put_enabled(filters)
  end

  # status filter is "active" or "inactive" or "all"
  defp maybe_put_enabled(opts, %{"status" => status}) when is_binary(status),
    do: maybe_put_enabled_from_status(opts, status)

  defp maybe_put_enabled(opts, %{status: status}) when is_binary(status),
    do: maybe_put_enabled_from_status(opts, status)

  defp maybe_put_enabled(opts, _), do: opts

  defp maybe_put_enabled_from_status(opts, "active"), do: Keyword.put(opts, :enabled, true)
  defp maybe_put_enabled_from_status(opts, "inactive"), do: Keyword.put(opts, :enabled, false)
  defp maybe_put_enabled_from_status(opts, _), do: opts

  # Apply filters safely in memory with enhanced search functionality
  defp apply_in_memory_filters(ui_profiles, filters) do
    q = get_filter(filters, :q, "")
    provider = get_filter(filters, :provider, "all")
    status = get_filter(filters, :status, "all")

    q_down = String.downcase(q)

    Enum.filter(ui_profiles, fn p ->
      # Enhanced search across name, model, tags, and ID
      search_match =
        q_down == "" or
          String.contains?(String.downcase(p.name || ""), q_down) or
          String.contains?(String.downcase(p.model || ""), q_down) or
          String.contains?(String.downcase(p.id || ""), q_down) or
          tags_contain_search(p.tags || [], q_down)

      # Robust provider filtering
      provider_match =
        provider in [nil, "", "all"] or
          p.provider == provider or
          String.downcase(p.provider || "") == String.downcase(provider)

      # Robust status filtering
      status_match =
        status in [nil, "", "all"] or
          p.status == status or
          String.downcase(p.status || "") == String.downcase(status)

      search_match and provider_match and status_match
    end)
  end

  # Helper to search within tags
  defp tags_contain_search(tags, search_term) when is_list(tags) do
    Enum.any?(tags, fn tag ->
      tag_str =
        case tag do
          atom when is_atom(atom) -> Atom.to_string(atom)
          str when is_binary(str) -> str
          _ -> ""
        end

      String.contains?(String.downcase(tag_str), search_term)
    end)
  end

  defp tags_contain_search(_, _), do: false

  defp get_filter(filters, key, default) when is_map(filters) do
    cond do
      Map.has_key?(filters, key) ->
        Map.get(filters, key) || default

      Map.has_key?(filters, Atom.to_string(key)) ->
        Map.get(filters, Atom.to_string(key)) || default

      true ->
        default
    end
  end

  @doc """
  Convert LLMProfile domain struct to comprehensive UI format.

  This function provides a complete conversion from domain objects to UI-friendly maps
  with proper null handling, datetime formatting, and all required UI fields including
  usage statistics, cost information, and configuration mapping.

  ## Examples

      iex> profile = %LLMProfile{name: "Test", provider: :openai, model: "gpt-4"}
      iex> convert_to_ui_format(profile)
      %{id: "...", name: "Test", provider: "openai", ...}
  """
  @spec convert_to_ui_format(LLMProfile.t()) :: ui_profile()
  def convert_to_ui_format(%LLMProfile{} = profile) do
    generation = profile.generation || %GenerationParams{}
    budgets = profile.budgets || %Budgets{}

    # Get provider information from database using provider_id
    provider_info = get_provider_info_for_ui(profile.provider_id)
    provider_string = provider_info[:name] || to_string(profile.provider_id)

    # Get provider-specific cost information
    cost_info = get_provider_cost_info(provider_string, profile.model)

    # Calculate derived fields with proper null handling
    status = if profile.enabled, do: "active", else: "inactive"

    # Build comprehensive UI profile with all required fields
    %{
      # Core identification fields
      id: safe_string(profile.id),
      name: safe_string(profile.name),
      provider: provider_string,
      provider_id: profile.provider_id,
      model: safe_string(profile.model),

      # Status and configuration
      status: status,
      enabled: profile.enabled,
      policy_version: safe_string(profile.policy_version, "1"),
      description: safe_string(Map.get(profile, :description), ""),

      # Generation parameters with null safety
      temperature: safe_float(generation.temperature, 0.7),
      max_tokens: safe_integer(generation.max_output_tokens, 2048),

      # Comprehensive generation configuration
      generation: %{
        temperature: safe_float(generation.temperature, 0.7),
        top_p: safe_float(generation.top_p, 1.0),
        max_output_tokens: safe_integer(generation.max_output_tokens, 2048),
        seed: generation.seed,
        presence_penalty: safe_float(generation.presence_penalty, 0.0),
        frequency_penalty: safe_float(generation.frequency_penalty, 0.0),
        stop: safe_list(generation.stop)
      },

      # Budget limits with null handling
      budgets: %{
        max_input_tokens: budgets.max_input_tokens,
        max_output_tokens: budgets.max_output_tokens,
        max_total_tokens: budgets.max_total_tokens,
        max_cost_eur: budgets.max_cost_eur,
        max_steps: budgets.max_steps
      },

      # Tools and configuration
      tools: safe_list(profile.tools),
      stop_list: safe_list(profile.stop_list),
      tags: safe_list(profile.tags),

      # Legacy config for backward compatibility
      config: %{
        temperature: safe_float(generation.temperature, 0.7),
        max_tokens: safe_integer(generation.max_output_tokens, 2048),
        top_p: safe_float(generation.top_p, 1.0),
        frequency_penalty: safe_float(generation.frequency_penalty, 0.0),
        presence_penalty: safe_float(generation.presence_penalty, 0.0),
        seed: generation.seed
      },

      # Datetime fields with proper formatting
      created_at: format_datetime_for_ui(profile.inserted_at),
      updated_at: format_datetime_for_ui(profile.updated_at),

      # Usage statistics (placeholders until actual tracking is implemented)
      last_used: "Never",
      usage_count: 0,
      usage_stats: %{
        total_requests: 0,
        total_tokens: 0,
        avg_response_time: 0,
        success_rate: 100.0,
        last_error: nil,
        error_count: 0
      },

      # Cost information with provider-specific data
      cost_per_1k_tokens: cost_info,
      estimated_cost_per_request: calculate_estimated_cost(generation, cost_info),

      # Provider-specific metadata
      provider_info: %{
        supports_streaming: provider_info[:supports_streaming] || false,
        supports_function_calling: provider_info[:supports_function_calling] || false,
        supports_vision: provider_info[:supports_vision] || false,
        max_context_length: provider_info[:max_context_length] || 4096
      },

      # UI-specific fields
      display_name: build_display_name(profile),
      search_text: build_search_text(profile),
      sort_key: String.downcase(safe_string(profile.name))
    }
  end

  # Domain -> UI read model mapping (legacy function, now delegates to convert_to_ui_format)
  defp to_ui_profile(%LLMProfile{} = profile) do
    convert_to_ui_format(profile)
  end

  # Get provider information from database for UI display
  defp get_provider_info_for_ui(provider_id) do
    case AgentWeb.Providers.get_provider(provider_id) do
      {:ok, provider} ->
        %{
          name: provider.name,
          type: provider.type,
          supports_streaming: true,  # Default assumption
          supports_function_calling: false,  # Default assumption
          supports_vision: false,  # Default assumption
          max_context_length: 4096  # Default assumption
        }
      {:error, _} ->
        %{
          name: "Unknown Provider",
          type: "unknown",
          supports_streaming: false,
          supports_function_calling: false,
          supports_vision: false,
          max_context_length: 4096
        }
    end
  end

  # Helper functions for UI conversion with comprehensive null handling and formatting

  # Safe string conversion with default fallback
  defp safe_string(nil), do: ""
  defp safe_string(value) when is_binary(value), do: value
  defp safe_string(value) when is_atom(value), do: Atom.to_string(value)
  defp safe_string(value), do: to_string(value)

  defp safe_string(nil, default), do: default
  defp safe_string(value, _default) when is_binary(value), do: value
  defp safe_string(value, _default) when is_atom(value), do: Atom.to_string(value)
  defp safe_string(value, default) when value == "", do: default
  defp safe_string(value, _default), do: to_string(value)

  # Safe atom to string conversion
  defp safe_atom_to_string(nil), do: ""
  defp safe_atom_to_string(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp safe_atom_to_string(value) when is_binary(value), do: value
  defp safe_atom_to_string(_), do: ""

  # Safe numeric conversions with defaults
  defp safe_float(nil, default), do: default
  defp safe_float(value, _default) when is_float(value), do: value
  defp safe_float(value, _default) when is_integer(value), do: value * 1.0

  defp safe_float(value, default) when is_binary(value) do
    case Float.parse(value) do
      {float_val, _} -> float_val
      :error -> default
    end
  end

  defp safe_float(_, default), do: default

  defp safe_integer(nil, default), do: default
  defp safe_integer(value, _default) when is_integer(value), do: value
  defp safe_integer(value, _default) when is_float(value), do: trunc(value)

  defp safe_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int_val, _} -> int_val
      :error -> default
    end
  end

  defp safe_integer(_, default), do: default

  # Safe list conversion
  defp safe_list(nil), do: []
  defp safe_list(list) when is_list(list), do: list
  defp safe_list(_), do: []

  # Enhanced datetime formatting for UI display
  defp format_datetime_for_ui(nil), do: "Never"

  defp format_datetime_for_ui(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  end

  defp format_datetime_for_ui(%NaiveDateTime{} = ndt) do
    case DateTime.from_naive(ndt, "Etc/UTC") do
      {:ok, dt} -> Calendar.strftime(dt, "%Y-%m-%d %H:%M")
      _ -> "Unknown"
    end
  end

  defp format_datetime_for_ui(_), do: "Unknown"

  # Get provider-specific cost information
  defp get_provider_cost_info(provider, model) do
    # Default cost structure
    default_costs = %{input: 0.0, output: 0.0}

    # Provider-specific cost mapping (placeholder - should be from configuration)
    case safe_atom_to_string(provider) do
      "openai" -> get_openai_costs(model)
      "anthropic" -> get_anthropic_costs(model)
      "google" -> get_google_costs(model)
      "azure" -> get_azure_costs(model)
      _ -> default_costs
    end
  end

  # Provider-specific cost functions (placeholders for actual cost data)
  defp get_openai_costs(model) do
    case String.downcase(model || "") do
      "gpt-4" -> %{input: 0.03, output: 0.06}
      "gpt-4-turbo" -> %{input: 0.01, output: 0.03}
      "gpt-3.5-turbo" -> %{input: 0.001, output: 0.002}
      "text-embedding-ada-002" -> %{input: 0.0001, output: 0.0}
      _ -> %{input: 0.0, output: 0.0}
    end
  end

  defp get_anthropic_costs(model) do
    case String.downcase(model || "") do
      "claude-3-opus" -> %{input: 0.015, output: 0.075}
      "claude-3-sonnet" -> %{input: 0.003, output: 0.015}
      "claude-3-haiku" -> %{input: 0.00025, output: 0.00125}
      _ -> %{input: 0.0, output: 0.0}
    end
  end

  defp get_google_costs(model) do
    case String.downcase(model || "") do
      "gemini-pro" -> %{input: 0.0005, output: 0.0015}
      "gemini-pro-vision" -> %{input: 0.0025, output: 0.01}
      _ -> %{input: 0.0, output: 0.0}
    end
  end

  defp get_azure_costs(model) do
    # Azure typically uses OpenAI pricing with potential enterprise discounts
    get_openai_costs(model)
  end

  # Calculate estimated cost per request based on generation parameters
  defp calculate_estimated_cost(generation, cost_info) do
    max_tokens = safe_integer(generation.max_output_tokens, 2048)
    # Assume ~1k input tokens
    input_cost = 1000 * cost_info.input / 1000
    output_cost = max_tokens * cost_info.output / 1000

    Float.round(input_cost + output_cost, 4)
  end

  # Get provider maximum context length
  defp get_provider_max_context(provider, model) do
    case {safe_atom_to_string(provider), String.downcase(model || "")} do
      {"openai", "gpt-4"} -> 128_000
      {"openai", "gpt-4-turbo"} -> 128_000
      {"openai", "gpt-3.5-turbo"} -> 16385
      {"anthropic", "claude-3-opus"} -> 200_000
      {"anthropic", "claude-3-sonnet"} -> 200_000
      {"anthropic", "claude-3-haiku"} -> 200_000
      {"google", "gemini-pro"} -> 32000
      # Conservative default
      _ -> 4096
    end
  end

  # Build display name for UI
  defp build_display_name(profile) do
    name = safe_string(profile.name)
    model = safe_string(profile.model)

    if name != "" do
      if model != "" and not String.contains?(name, model) do
        "#{name} (#{model})"
      else
        name
      end
    else
      model
    end
  end

  # Build search text for enhanced filtering
  defp build_search_text(profile) do
    parts = [
      safe_string(profile.name),
      safe_string(profile.model),
      to_string(profile.provider_id),
      safe_string(profile.policy_version),
      format_tags_for_search(profile.tags)
    ]

    parts
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
    |> String.downcase()
  end

  # Format tags for search indexing
  defp format_tags_for_search(nil), do: ""
  defp format_tags_for_search([]), do: ""

  defp format_tags_for_search(tags) when is_list(tags) do
    tags
    |> Enum.map(&safe_atom_to_string/1)
    |> Enum.join(" ")
  end

  defp format_tags_for_search(_), do: ""

  defp format_datetime(nil), do: "Never"

  defp format_datetime(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d")

  defp format_datetime(%NaiveDateTime{} = ndt) do
    # Your original code assumed naive UTC — keeping same semantics.
    case DateTime.from_naive(ndt, "Etc/UTC") do
      {:ok, dt} -> Calendar.strftime(dt, "%Y-%m-%d")
      _ -> "Unknown"
    end
  end

  defp format_datetime(_), do: "Unknown"
end
