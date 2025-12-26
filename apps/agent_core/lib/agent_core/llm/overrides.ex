defmodule AgentCore.Llm.Overrides do
  @moduledoc """
  Typed, UI-ready overrides schema for LLM invocation resolution.

  - Converts loose maps/keywords into a well-defined struct
  - Validates allowed keys and basic types
  - Keeps errors in the same machine-friendly format as Validator
  """

  @enforce_keys []
  defstruct generation: %{},
            budgets: %{},
            tools: nil,
            stop_list: nil,
            trace_id: nil

  @type t :: %__MODULE__{
          generation: map(),
          budgets: map(),
          tools: nil | list(),
          stop_list: nil | list(),
          trace_id: nil | String.t()
        }

  @type error :: %{field: String.t(), code: atom(), message: String.t(), value: term()}

  @allowed_top_keys ~w(generation budgets tools stop_list trace_id)a

  @spec from(any(), keyword()) :: {:ok, t()} | {:error, [error()]}
  def from(input, opts \\ []) do
    strict? = Keyword.get(opts, :strict, true)

    map =
      cond do
        is_map(input) -> input
        is_list(input) -> Map.new(input)
        is_nil(input) -> %{}
        true -> %{}
      end

    # allow both atom and string keys for convenience:
    map = normalize_top_level_keys(map)

    errors =
      []
      |> validate_top_keys(map, strict?)
      |> validate_trace_id(map)

    if errors != [] do
      {:error, Enum.reverse(errors)}
    else
      {:ok,
       %__MODULE__{
         generation: Map.get(map, :generation, %{}) |> ensure_map(),
         budgets: Map.get(map, :budgets, %{}) |> ensure_map(),
         tools: Map.get(map, :tools, nil),
         stop_list: Map.get(map, :stop_list, nil),
         trace_id: normalize_trace_id(Map.get(map, :trace_id))
       }}
    end
  end

  def to_map(%__MODULE__{} = o) do
    %{}
    |> put_if_present(:generation, o.generation, %{})
    |> put_if_present(:budgets, o.budgets, %{})
    |> put_if_present(:tools, o.tools, nil)
    |> put_if_present(:stop_list, o.stop_list, nil)
    |> put_if_present(:trace_id, o.trace_id, nil)
  end

  # --- internals ---

  defp normalize_top_level_keys(map) do
    # Only normalize known keys so we don't “invent” new keys in strict mode.
    Enum.reduce([:generation, :budgets, :tools, :stop_list, :trace_id], map, fn k, acc ->
      sk = Atom.to_string(k)

      cond do
        Map.has_key?(acc, k) ->
          acc

        Map.has_key?(acc, sk) ->
          val = Map.get(acc, sk)
          acc |> Map.delete(sk) |> Map.put(k, val)

        true ->
          acc
      end
    end)
  end

  defp validate_top_keys(errors, map, strict?) do
    unknown =
      map
      |> Map.keys()
      |> Enum.reject(&(&1 in @allowed_top_keys))

    if strict? and unknown != [] do
      Enum.reduce(unknown, errors, fn k, acc ->
        [err("overrides.#{k}", :unsupported, "Unknown override key", k) | acc]
      end)
    else
      errors
    end
  end

  defp validate_trace_id(errors, map) do
    case Map.get(map, :trace_id) do
      nil ->
        errors

      v when is_binary(v) ->
        if String.trim(v) == "" do
          [err("overrides.trace_id", :invalid, "trace_id must be a non-empty string", v) | errors]
        else
          errors
        end

      v ->
        [err("overrides.trace_id", :invalid, "trace_id must be a string", v) | errors]
    end
  end

  defp normalize_trace_id(nil), do: nil

  defp normalize_trace_id(v) when is_binary(v) do
    t = String.trim(v)
    if t == "", do: nil, else: t
  end

  defp normalize_trace_id(_), do: nil

  defp ensure_map(v) when is_map(v), do: v
  defp ensure_map(_), do: %{}

  defp put_if_present(m, _k, v, default) when v == default, do: m
  defp put_if_present(m, _k, nil, _default), do: m
  defp put_if_present(m, k, v, _default), do: Map.put(m, k, v)

  defp err(field, code, message, value),
    do: %{field: field, code: code, message: message, value: value}
end
