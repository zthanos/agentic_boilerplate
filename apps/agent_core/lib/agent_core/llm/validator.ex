defmodule AgentCore.Llm.Validator do
  @moduledoc """
  Validates and normalizes LLM domain structs (profiles, provider, model, params).

  Goals:
  - Pure domain (no Ecto).
  - Returns {:ok, normalized_profile} or {:error, errors}.
  - Errors are machine-friendly and UI-ready.
  """

  alias AgentCore.Llm.{LLMProfile, Provider, ModelRef, GenerationParams, Budgets}

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
      |> require_struct("provider", profile.provider, Provider)
      |> require_struct("model", profile.model, ModelRef)
      |> validate_provider(profile.provider)
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
        provider: normalize_provider(p.provider),
        model: normalize_model(p.model),
        generation: normalize_generation(p.generation),
        budgets: normalize_budgets(p.budgets)
    }
  end

  defp normalize_provider(%Provider{} = pr) do
    %Provider{
      pr
      | type: pr.type || :openai_compatible,
        base_url: normalize_string(pr.base_url),
        api_key: normalize_string(pr.api_key),
        default_headers: pr.default_headers || %{},
        request_timeout_ms: pr.request_timeout_ms || 60_000,
        retries: pr.retries || 1,
        retry_backoff_ms: pr.retry_backoff_ms || 250
    }
  end

  defp normalize_provider(other), do: other

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

  # ---------------------------------------------------------------------------
  # Provider validation
  # ---------------------------------------------------------------------------

  defp validate_provider(errors, %Provider{} = p) do
    errors
    |> validate_provider_type(p.type)
    |> require_string("provider.base_url", p.base_url)
    |> validate_base_url(p.base_url)
    |> validate_positive_int("provider.request_timeout_ms", p.request_timeout_ms, min: 1_000, max: 300_000)
    |> validate_int_range("provider.retries", p.retries, min: 0, max: 10)
    |> validate_positive_int("provider.retry_backoff_ms", p.retry_backoff_ms, min: 0, max: 60_000)
    |> validate_map("provider.default_headers", p.default_headers)
  end

  defp validate_provider(errors, _), do: errors

  defp validate_provider_type(errors, :openai_compatible), do: errors

  defp validate_provider_type(errors, other) do
    add_error(errors, "provider.type", :unsupported, "Unsupported provider type", other)
  end

  defp validate_base_url(errors, nil), do: errors

  defp validate_base_url(errors, base_url) when is_binary(base_url) do
    uri = URI.parse(base_url)

    errors =
      cond do
        uri.scheme not in ["http", "https"] ->
          add_error(errors, "provider.base_url", :invalid, "base_url must start with http:// or https://", base_url)

        is_nil(uri.host) ->
          add_error(errors, "provider.base_url", :invalid, "base_url must include a host", base_url)

        true ->
          errors
      end

    if String.ends_with?(base_url, "/v1") do
      errors
    else
      add_error(errors, "provider.base_url", :invalid, "base_url should typically end with /v1 for OpenAI-compatible servers", base_url)
    end
  end

  defp validate_base_url(errors, other) do
    add_error(errors, "provider.base_url", :invalid, "base_url must be a string", other)
  end

  # ---------------------------------------------------------------------------
  # Model validation
  # ---------------------------------------------------------------------------

  defp validate_model(errors, %ModelRef{} = m) do
    errors
    |> require_string("model.name", m.name)
    |> validate_optional_pos_int("model.context_window", m.context_window, max: 1_000_000)
  end

  defp validate_model(errors, _), do: errors

  # ---------------------------------------------------------------------------
  # Generation params validation
  # ---------------------------------------------------------------------------

  defp validate_generation(errors, %GenerationParams{} = g) do
    errors
    |> validate_float_range("generation.temperature", g.temperature, min: 0.0, max: 2.0)
    |> validate_float_range("generation.top_p", g.top_p, min: 0.0, max: 1.0)
    |> validate_optional_pos_int("generation.max_output_tokens", g.max_output_tokens, max: 1_000_000)
    |> validate_optional_int_range("generation.seed", g.seed, min: 0, max: 2_147_483_647)
    |> validate_optional_float_range("generation.presence_penalty", g.presence_penalty, min: -2.0, max: 2.0)
    |> validate_optional_float_range("generation.frequency_penalty", g.frequency_penalty, min: -2.0, max: 2.0)
    |> validate_stop_list(g.stop)
  end

  defp validate_generation(errors, nil), do: errors

  defp validate_generation(errors, other) do
    add_error(errors, "generation", :invalid, "generation must be a GenerationParams struct", other)
  end

  defp validate_stop_list(errors, nil), do: errors

  defp validate_stop_list(errors, stops) when is_list(stops) do
    valid? =
      Enum.all?(stops, fn
        s when is_binary(s) -> byte_size(String.trim(s)) > 0
        _ -> false
      end)

    if valid? do
      errors
    else
      add_error(errors, "generation.stop", :invalid, "stop must be a list of non-empty strings", stops)
    end
  end

  defp validate_stop_list(errors, other) do
    add_error(errors, "generation.stop", :invalid, "stop must be a list of strings", other)
  end

  # ---------------------------------------------------------------------------
  # Budgets validation
  # ---------------------------------------------------------------------------

  defp validate_budgets(errors, %Budgets{} = b) do
    errors
    |> validate_optional_pos_int("budgets.max_input_tokens", b.max_input_tokens, max: 10_000_000)
    |> validate_optional_pos_int("budgets.max_output_tokens", b.max_output_tokens, max: 10_000_000)
    |> validate_optional_pos_int("budgets.max_total_tokens", b.max_total_tokens, max: 10_000_000)
    |> validate_optional_float_range("budgets.max_cost_eur", b.max_cost_eur, min: 0.0, max: 10_000.0)
    |> validate_optional_pos_int("budgets.max_steps", b.max_steps, max: 1_000)
    |> validate_budget_consistency(b)
  end

  defp validate_budgets(errors, nil), do: errors

  defp validate_budgets(errors, other) do
    add_error(errors, "budgets", :invalid, "budgets must be a Budgets struct", other)
  end

  defp validate_budget_consistency(errors, %Budgets{} = b) do
    cond do
      is_integer(b.max_total_tokens) and is_integer(b.max_input_tokens) and b.max_input_tokens > b.max_total_tokens ->
        add_error(errors, "budgets.max_input_tokens", :invalid, "max_input_tokens cannot exceed max_total_tokens", b.max_input_tokens)

      is_integer(b.max_total_tokens) and is_integer(b.max_output_tokens) and b.max_output_tokens > b.max_total_tokens ->
        add_error(errors, "budgets.max_output_tokens", :invalid, "max_output_tokens cannot exceed max_total_tokens", b.max_output_tokens)

      true ->
        errors
    end
  end

  # ---------------------------------------------------------------------------
  # Tags validation
  # ---------------------------------------------------------------------------

  defp validate_tags(errors, tags) when is_list(tags) do
    if Enum.all?(tags, &is_binary/1) do
      errors
    else
      add_error(errors, "tags", :invalid, "tags must be a list of strings", tags)
    end
  end

  defp validate_tags(errors, nil), do: errors

  defp validate_tags(errors, other) do
    add_error(errors, "tags", :invalid, "tags must be a list of strings", other)
  end

  # ---------------------------------------------------------------------------
  # Generic validators / helpers
  # ---------------------------------------------------------------------------

  defp require_string(errors, field, nil) do
    add_error(errors, field, :required, "Value is required", nil)
  end

  defp require_string(errors, field, value) when is_binary(value) do
    if String.trim(value) == "" do
      add_error(errors, field, :required, "Value is required", value)
    else
      errors
    end
  end

  defp require_string(errors, field, value) do
    add_error(errors, field, :required, "Value must be a string", value)
  end

  # NOTE: This pattern ensures "value is a struct of module `mod`".
  # It works because structs are maps with the __struct__ field set to the module.
  defp require_struct(errors, _field, %mod{} = _value, mod), do: errors

  defp require_struct(errors, field, value, mod) do
    add_error(errors, field, :required, "Expected #{inspect(mod)} struct", value)
  end

  defp validate_map(errors, _field, value) when is_map(value), do: errors
  defp validate_map(errors, field, value), do: add_error(errors, field, :invalid, "Expected a map", value)

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
  defp validate_optional_float_range(errors, field, value, opts), do: validate_float_range(errors, field, value, opts)

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
