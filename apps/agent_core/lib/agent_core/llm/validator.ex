defmodule AgentCore.Llm.Validator do
  @moduledoc """
  Validates and normalizes LLM domain structs (profiles, provider, model, params).

  Goals:
  - Pure domain (no Ecto).
  - Returns {:ok, normalized_profile} or {:error, errors}.
  - Errors are machine-friendly and UI-ready.
  """

  alias AgentCore.Llm.{LLMProfile, ModelRef, GenerationParams, Budgets}

  @type error :: %{
          field: String.t(),
          code: atom(),
          message: String.t(),
          value: term()
        }

  @spec validate_profile(LLMProfile.t()) :: {:ok, LLMProfile.t()} | {:error, [error()]}
  def validate_profile(%LLMProfile{} = profile) do
    profile = normalize_profile(profile)

    errors =
      []
      |> require_string("name", profile.name)
      |> require_provider_id("provider_id", profile.provider_id)
      |> require_struct("model", profile.model, ModelRef)
      |> validate_provider_id(profile.provider_id)
      |> validate_model(profile.model)
      |> validate_generation(profile.generation)
      |> validate_budgets(profile.budgets)
      |> validate_tags(profile.tags)

    if errors == [] do
      {:ok, profile}
    else
      {:error, Enum.reverse(errors)}
    end
  end

  # ---------------------------------------------------------------------------
  # Normalization
  # ---------------------------------------------------------------------------

  @spec normalize_profile(LLMProfile.t()) :: LLMProfile.t()
  def normalize_profile(%LLMProfile{} = p) do
    %LLMProfile{
      p
      | name: normalize_string(p.name),
        enabled: if(is_boolean(p.enabled), do: p.enabled, else: true),
        tags: normalize_tags(p.tags),
        provider_id: normalize_provider_id(p.provider_id),
        model: normalize_model(p.model),
        generation: normalize_generation(p.generation),
        budgets: normalize_budgets(p.budgets)
    }
  end

  defp normalize_provider_id(provider_id) when is_binary(provider_id) or is_integer(provider_id) do
    to_string(provider_id)
  end

  defp normalize_provider_id(nil), do: nil
  defp normalize_provider_id(other), do: other

  defp normalize_model(%ModelRef{} = m) do
    %ModelRef{
      m
      | name: normalize_string(m.name),
        family: m.family,
        context_window: m.context_window,
        supports_json: m.supports_json,
        supports_tools: m.supports_tools
    }
  end

  defp normalize_model(other), do: other

  defp normalize_generation(%GenerationParams{} = g) do
    %GenerationParams{
      g
      | temperature: default_float(g.temperature, 0.2),
        top_p: default_float(g.top_p, 1.0),
        max_output_tokens: g.max_output_tokens,
        seed: g.seed,
        presence_penalty: g.presence_penalty,
        frequency_penalty: g.frequency_penalty,
        stop: normalize_stop(g.stop)
    }
  end

  defp normalize_generation(nil), do: %GenerationParams{}
  defp normalize_generation(other), do: other

  defp normalize_budgets(%Budgets{} = b), do: b
  defp normalize_budgets(nil), do: %Budgets{}
  defp normalize_budgets(other), do: other

  defp normalize_string(nil), do: nil
  defp normalize_string(s) when is_binary(s), do: s |> String.trim() |> empty_to_nil()
  defp normalize_string(s), do: s

  defp empty_to_nil(""), do: nil
  defp empty_to_nil(s), do: s

  defp default_float(nil, default), do: default
  defp default_float(v, _default) when is_number(v), do: v
  defp default_float(v, _default), do: v

  defp normalize_tags(nil), do: []

  defp normalize_tags(tags) when is_list(tags) do
    tags
    |> Enum.map(&normalize_string/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_tags(_), do: []

  defp normalize_stop(nil), do: nil

  defp normalize_stop(stops) when is_list(stops) do
    cleaned =
      stops
      |> Enum.map(&normalize_string/1)
      |> Enum.reject(&is_nil/1)

    if cleaned == [], do: nil, else: cleaned
  end

  defp normalize_stop(_), do: nil

  defp require_provider_id(errors, field_name, provider_id) do
    case provider_id do
      nil -> add_error(errors, field_name, :required, "Provider ID is required", nil)
      "" -> add_error(errors, field_name, :required, "Provider ID cannot be empty", "")
      id when is_binary(id) or is_integer(id) -> errors
      _ -> add_error(errors, field_name, :invalid, "Provider ID must be a valid ID", provider_id)
    end
  end

  defp validate_provider_id(errors, provider_id) do
    # Simple validation - just check that it's not nil/empty
    # More complex validation (checking database) should be done at the web layer
    case provider_id do
      nil -> add_error(errors, "provider_id", :required, "Provider ID is required", nil)
      "" -> add_error(errors, "provider_id", :required, "Provider ID cannot be empty", "")
      id when is_binary(id) or is_integer(id) -> errors
      _ -> add_error(errors, "provider_id", :invalid, "Provider ID must be a valid ID", provider_id)
    end
  end

  # ---------------------------------------------------------------------------
  # Model validation (typed; require_struct already executed)
  # ---------------------------------------------------------------------------

  defp validate_model(errors, %ModelRef{} = m) do
    errors
    |> require_string("model.name", m.name)
    |> validate_optional_pos_int("model.context_window", m.context_window, max: 1_000_000)
  end

  # ---------------------------------------------------------------------------
  # Generation params validation (typed; normalize_generation ensures struct)
  # ---------------------------------------------------------------------------

  defp validate_generation(errors, %GenerationParams{} = g) do
    errors
    |> validate_float_range("generation.temperature", g.temperature, min: 0.0, max: 2.0)
    |> validate_float_range("generation.top_p", g.top_p, min: 0.0, max: 1.0)
    |> validate_optional_pos_int("generation.max_output_tokens", g.max_output_tokens,
      max: 1_000_000
    )
    |> validate_optional_int_range("generation.seed", g.seed, min: 0, max: 2_147_483_647)
    |> validate_optional_float_range("generation.presence_penalty", g.presence_penalty,
      min: -2.0,
      max: 2.0
    )
    |> validate_optional_float_range("generation.frequency_penalty", g.frequency_penalty,
      min: -2.0,
      max: 2.0
    )
    |> validate_stop_list(g.stop)
  end

  defp validate_stop_list(errors, nil), do: errors

  defp validate_stop_list(errors, stops) when is_list(stops) do
    valid? =
      Enum.all?(stops, fn
        s when is_binary(s) ->
          s
          |> String.trim()
          |> byte_size() > 0

        _ ->
          false
      end)

    if valid? do
      errors
    else
      add_error(
        errors,
        "generation.stop",
        :invalid,
        "stop must be a list of non-empty strings",
        stops
      )
    end
  end

  # ---------------------------------------------------------------------------
  # Budgets validation (typed; normalize_budgets ensures struct)
  # ---------------------------------------------------------------------------

  defp validate_budgets(errors, %Budgets{} = b) do
    errors
    |> validate_optional_pos_int("budgets.max_input_tokens", b.max_input_tokens, max: 10_000_000)
    |> validate_optional_pos_int("budgets.max_output_tokens", b.max_output_tokens,
      max: 10_000_000
    )
    |> validate_optional_pos_int("budgets.max_total_tokens", b.max_total_tokens, max: 10_000_000)
    |> validate_optional_float_range("budgets.max_cost_eur", b.max_cost_eur,
      min: 0.0,
      max: 10_000.0
    )
    |> validate_optional_pos_int("budgets.max_steps", b.max_steps, max: 1_000)
    |> validate_budget_consistency(b)
  end

  defp validate_budget_consistency(errors, %Budgets{} = b) do
    cond do
      is_integer(b.max_total_tokens) and is_integer(b.max_input_tokens) and
          b.max_input_tokens > b.max_total_tokens ->
        add_error(
          errors,
          "budgets.max_input_tokens",
          :invalid,
          "max_input_tokens cannot exceed max_total_tokens",
          b.max_input_tokens
        )

      is_integer(b.max_total_tokens) and is_integer(b.max_output_tokens) and
          b.max_output_tokens > b.max_total_tokens ->
        add_error(
          errors,
          "budgets.max_output_tokens",
          :invalid,
          "max_output_tokens cannot exceed max_total_tokens",
          b.max_output_tokens
        )

      true ->
        errors
    end
  end

  # ---------------------------------------------------------------------------
  # Tags validation (typed; normalize_tags ensures list)
  # ---------------------------------------------------------------------------

  defp validate_tags(errors, tags) when is_list(tags) do
    if Enum.all?(tags, &is_binary/1) do
      errors
    else
      add_error(errors, "tags", :invalid, "tags must be a list of strings", tags)
    end
  end

  # ---------------------------------------------------------------------------
  # Generic validators / helpers
  # ---------------------------------------------------------------------------

  # NOTE: strict binary clause to avoid Dialyzer unreachable-clauses when call-sites are typed.
  defp require_string(errors, field, value) when is_binary(value) do
    if String.trim(value) == "" do
      add_error(errors, field, :required, "Value is required", value)
    else
      errors
    end
  end

  # Ensures "value is a struct of module `mod`".
  defp require_struct(errors, _field, %mod{} = _value, mod), do: errors

  defp require_struct(errors, field, value, mod) do
    add_error(errors, field, :required, "Expected #{inspect(mod)} struct", value)
  end

  defp validate_map(errors, _field, value) when is_map(value), do: errors

  defp validate_map(errors, field, value),
    do: add_error(errors, field, :invalid, "Expected a map", value)

  defp validate_positive_int(errors, field, value, opts) do
    min = Keyword.get(opts, :min, 1)
    max = Keyword.get(opts, :max, :infinity)

    cond do
      not is_integer(value) ->
        add_error(errors, field, :invalid, "Expected an integer", value)

      value < min ->
        add_error(errors, field, :invalid, "Must be >= #{min}", value)

      max != :infinity and value > max ->
        add_error(errors, field, :invalid, "Must be <= #{max}", value)

      true ->
        errors
    end
  end

  defp validate_int_range(errors, field, value, opts) do
    min = Keyword.fetch!(opts, :min)
    max = Keyword.fetch!(opts, :max)

    cond do
      not is_integer(value) ->
        add_error(errors, field, :invalid, "Expected an integer", value)

      value < min or value > max ->
        add_error(errors, field, :invalid, "Must be between #{min} and #{max}", value)

      true ->
        errors
    end
  end

  defp validate_float_range(errors, field, value, opts) do
    min = Keyword.fetch!(opts, :min)
    max = Keyword.fetch!(opts, :max)

    cond do
      not is_number(value) ->
        add_error(errors, field, :invalid, "Expected a number", value)

      value < min or value > max ->
        add_error(errors, field, :invalid, "Must be between #{min} and #{max}", value)

      true ->
        errors
    end
  end

  defp validate_optional_float_range(errors, _field, nil, _opts), do: errors

  defp validate_optional_float_range(errors, field, value, opts),
    do: validate_float_range(errors, field, value, opts)

  defp validate_optional_int_range(errors, _field, nil, _opts), do: errors

  defp validate_optional_int_range(errors, field, value, opts) do
    min = Keyword.fetch!(opts, :min)
    max = Keyword.fetch!(opts, :max)

    cond do
      not is_integer(value) ->
        add_error(errors, field, :invalid, "Expected an integer", value)

      value < min or value > max ->
        add_error(errors, field, :invalid, "Must be between #{min} and #{max}", value)

      true ->
        errors
    end
  end

  defp validate_optional_pos_int(errors, _field, nil, _opts), do: errors

  defp validate_optional_pos_int(errors, field, value, opts) do
    max = Keyword.get(opts, :max, :infinity)

    cond do
      not is_integer(value) ->
        add_error(errors, field, :invalid, "Expected an integer", value)

      value <= 0 ->
        add_error(errors, field, :invalid, "Must be a positive integer", value)

      max != :infinity and value > max ->
        add_error(errors, field, :invalid, "Must be <= #{max}", value)

      true ->
        errors
    end
  end

  defp add_error(errors, field, code, message, value) do
    [%{field: field, code: code, message: message, value: value} | errors]
  end
end
