defmodule AgentCore.Llm.Resolver do
  alias AgentCore.Llm.{InvocationConfig, Overrides}

  @clear :__clear__

  @merge_policy %{
    # domains (maps) -> deep merged anyway
    generation: :merge,
    budgets: :merge,

    # lists
    # profile ∪ overrides
    tools: :union,
    # overrides replace profile
    stop_list: :replace
  }

  @doc """
  Resolve a profile plus runtime overrides into a deterministic InvocationConfig snapshot.

  `overrides` can be:
    - map with nested domains (generation/budgets/tools/stop_list)
    - or keyword list (will be converted to map)

  Clear semantics:
    - set a domain (or field) to :__clear__ to clear it deterministically.
      e.g. %{stop_list: :__clear__}
      e.g. %{generation: %{temperature: :__clear__}}
  """
  def resolve(profile, overrides \\ %{}, policy \\ @merge_policy) do
    # overrides = normalize_overrides(overrides)
    overrides_map =
      case overrides do
        %Overrides{} = o ->
          Overrides.to_map(o)

        other ->
          case Overrides.from(other, strict: true) do
            {:ok, o} -> Overrides.to_map(o)
            {:error, errs} -> raise ArgumentError, "Invalid overrides: #{inspect(errs)}"
          end
      end

    base = profile_to_base_map(profile)

    merged =
      base
      |> deep_merge(overrides_map, policy)
      |> canonicalize_final()

    %InvocationConfig{
      profile_id: merged.profile_id,
      profile_name: merged.profile_name,
      provider: merged.provider,
      model: merged.model,
      generation: merged.generation,
      budgets: merged.budgets,
      tools: merged.tools,
      stop_list: merged.stop_list,
      resolved_at: DateTime.utc_now(),
      overrides: canonicalize_overrides(overrides),
      fingerprint: fingerprint(merged)
    }
  end

  # -------------------------
  # Input normalization
  # -------------------------

  # defp normalize_overrides(overrides) when is_list(overrides), do: Map.new(overrides)
  # defp normalize_overrides(overrides) when is_map(overrides), do: overrides
  # defp normalize_overrides(_), do: %{}

  # Convert profile struct into a plain map with only the domains we care about.
  # This prevents accidental merging of internal fields.
  defp profile_to_base_map(profile) do
    %{
      profile_id: Map.fetch!(profile, :id),
      profile_name: Map.get(profile, :name),
      provider: Map.get(profile, :provider),
      model: Map.get(profile, :model),
      generation: Map.get(profile, :generation, %{}),
      budgets: Map.get(profile, :budgets, %{}),
      tools: Map.get(profile, :tools, []),
      # preferred: explicit profile.stop_list
      # fallback: generation.stop (legacy)
      stop_list:
        Map.get(profile, :stop_list) ||
          case Map.get(profile, :generation) do
            %AgentCore.Llm.GenerationParams{stop: stops} -> stops
            _ -> []
          end
    }
  end

  # -------------------------
  # Deep merge with clear semantics
  # -------------------------

  defp deep_merge(base, overrides, policy) when is_map(base) and is_map(overrides) do
    Map.merge(base, overrides, fn key, left, right ->
      merge_value(key, left, right, policy)
    end)
  end

  defp merge_value(_key, _left, @clear, _policy), do: default_for_clear()
  defp merge_value(_key, left, right, _policy) when right == nil, do: left

  # both maps => recurse (deep merge)
  defp merge_value(_key, left, right, policy) when is_map(left) and is_map(right) do
    deep_merge(left, right, policy)
  end

  # lists => apply per-key policy
  defp merge_value(key, left, right, policy) when is_list(left) and is_list(right) do
    list_policy = Map.get(policy, key, :replace)
    merge_list_by_policy(list_policy, left, assumed_list(right))
  end

  # if profile has nil and override has list (or vice versa)
  defp merge_value(key, left, right, policy) when is_list(right) do
    list_policy = Map.get(policy, key, :replace)
    merge_list_by_policy(list_policy, assumed_list(left), assumed_list(right))
  end

  # scalar => override
  defp merge_value(_key, _left, right, _policy), do: right

  defp default_for_clear(), do: nil

  defp assumed_list(nil), do: []
  defp assumed_list(v) when is_list(v), do: v
  defp assumed_list(_), do: []

  defp merge_list_by_policy(:replace, _left, right), do: right
  defp merge_list_by_policy(:append, left, right), do: left ++ right
  defp merge_list_by_policy(:union, left, right), do: left ++ right
  defp merge_list_by_policy(_unknown, _left, right), do: right

  # -------------------------
  # Canonicalization rules (determinism)
  # -------------------------

  defp canonicalize_final(m) do
    m
    |> canonicalize_generation()
    |> canonicalize_budgets()
    |> canonicalize_tools()
    |> canonicalize_stop_list()
  end

  defp canonicalize_overrides(overrides) when is_map(overrides) do
    overrides
    |> canonicalize_stop_list_in_map()
    |> canonicalize_tools_in_map()
  end

  defp canonicalize_generation(m) do
    gen = Map.get(m, :generation) || %{}

    gen =
      gen
      |> drop_nil_map_values()
      |> normalize_numeric(:temperature, 0.0, 2.0)
      |> normalize_numeric(:top_p, 0.0, 1.0)
      |> normalize_int(:max_output_tokens, 1, 200_000)
      |> normalize_int(:seed, 0, 2_147_483_647)

    Map.put(m, :generation, gen)
  end

  defp canonicalize_budgets(m) do
    b = Map.get(m, :budgets) || %{}

    b =
      b
      |> drop_nil_map_values()
      |> normalize_int(:request_timeout_ms, 1_000, 600_000)
      |> normalize_int(:max_retries, 0, 10)

    Map.put(m, :budgets, b)
  end

  defp canonicalize_tools(m) do
    tools =
      m
      |> Map.get(:tools, [])
      |> List.wrap()
      |> Enum.map(&normalize_tool/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort()

    Map.put(m, :tools, tools)
  end

  defp canonicalize_stop_list(m) do
    stop_list =
      m
      |> Map.get(:stop_list, [])
      |> List.wrap()
      |> Enum.map(&normalize_stop/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort()

    Map.put(m, :stop_list, stop_list)
  end

  defp canonicalize_stop_list_in_map(m) do
    case Map.fetch(m, :stop_list) do
      {:ok, v} when v == @clear ->
        Map.put(m, :stop_list, @clear)

      {:ok, v} ->
        Map.put(
          m,
          :stop_list,
          v
          |> List.wrap()
          |> Enum.map(&normalize_stop/1)
          |> Enum.reject(&is_nil/1)
          |> Enum.uniq()
          |> Enum.sort()
        )

      :error ->
        m
    end
  end

  defp canonicalize_tools_in_map(m) do
    case Map.fetch(m, :tools) do
      {:ok, v} when v == @clear ->
        Map.put(m, :tools, @clear)

      {:ok, v} ->
        Map.put(
          m,
          :tools,
          v
          |> List.wrap()
          |> Enum.map(&normalize_tool/1)
          |> Enum.reject(&is_nil/1)
          |> Enum.uniq()
          |> Enum.sort()
        )

      :error ->
        m
    end
  end

  defp normalize_stop(s) when is_binary(s) do
    t = String.trim(s)
    if byte_size(t) > 0, do: t, else: nil
  end

  defp normalize_stop(_), do: nil

  defp normalize_tool(t) when is_atom(t), do: Atom.to_string(t)

  defp normalize_tool(t) when is_binary(t) do
    s = String.trim(t)
    if s == "", do: nil, else: s
  end

  defp normalize_tool(_), do: nil

  defp drop_nil_map_values(map) when is_map(map) do
    map
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp normalize_numeric(map, key, min, max) do
    case Map.fetch(map, key) do
      {:ok, v} when is_number(v) ->
        Map.put(map, key, clamp_float(v, min, max))

      {:ok, v} when is_binary(v) ->
        case Float.parse(v) do
          {f, _} -> Map.put(map, key, clamp_float(f, min, max))
          :error -> Map.delete(map, key)
        end

      _ ->
        map
    end
  end

  defp normalize_int(map, key, min, max) do
    case Map.fetch(map, key) do
      {:ok, v} when is_integer(v) ->
        Map.put(map, key, clamp_int(v, min, max))

      {:ok, v} when is_binary(v) ->
        case Integer.parse(v) do
          {i, _} -> Map.put(map, key, clamp_int(i, min, max))
          :error -> Map.delete(map, key)
        end

      _ ->
        map
    end
  end

  defp clamp_float(v, min, max) do
    v
    |> max(min)
    |> min(max)
  end

  defp clamp_int(v, min, max) do
    v
    |> max(min)
    |> min(max)
  end

  # -------------------------
  # Fingerprint (deterministic)
  # -------------------------

  defp fingerprint(resolved_map) do
    # We want a stable hash; create a canonical term
    canonical =
      resolved_map
      |> Map.take([:profile_id, :provider, :model, :generation, :budgets, :tools, :stop_list])
      |> deep_sort_keys()

    :crypto.hash(:sha256, :erlang.term_to_binary(canonical))
    |> Base.encode16(case: :lower)
  end

  defp deep_sort_keys(term) when is_map(term) do
    term
    |> Enum.map(fn {k, v} -> {k, deep_sort_keys(v)} end)
    |> Enum.sort_by(fn {k, _v} -> to_string(k) end)
    |> Map.new()
  end

  defp deep_sort_keys(term) when is_list(term), do: Enum.map(term, &deep_sort_keys/1)
  defp deep_sort_keys(term), do: term
end
