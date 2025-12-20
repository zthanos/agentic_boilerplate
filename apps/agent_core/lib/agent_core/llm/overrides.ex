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
            stop_list: nil

  @type t :: %__MODULE__{
          generation: map(),
          budgets: map(),
          tools: nil | list(),
          stop_list: nil | list()
        }

  @type error :: %{field: String.t(), code: atom(), message: String.t(), value: term()}

  @allowed_top_keys ~w(generation budgets tools stop_list)a

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

    errors = validate_top_keys(map, strict?)

    if errors != [] do
      {:error, Enum.reverse(errors)}
    else
      {:ok,
       %__MODULE__{
         generation: Map.get(map, :generation, %{}) |> ensure_map(),
         budgets: Map.get(map, :budgets, %{}) |> ensure_map(),
         tools: Map.get(map, :tools, nil),
         stop_list: Map.get(map, :stop_list, nil)
       }}
    end
  end

  def to_map(%__MODULE__{} = o) do
    %{}
    |> put_if_present(:generation, o.generation, %{})
    |> put_if_present(:budgets, o.budgets, %{})
    |> put_if_present(:tools, o.tools, nil)
    |> put_if_present(:stop_list, o.stop_list, nil)
  end

  # --- internals ---

  defp validate_top_keys(map, strict?) do
    unknown =
      map
      |> Map.keys()
      |> Enum.reject(&(&1 in @allowed_top_keys))

    if strict? and unknown != [] do
      Enum.reduce(unknown, [], fn k, acc ->
        [err("overrides.#{k}", :unsupported, "Unknown override key", k) | acc]
      end)
    else
      []
    end
  end

  defp ensure_map(v) when is_map(v), do: v
  defp ensure_map(_), do: %{}

  defp put_if_present(m, _k, v, default) when v == default, do: m
  defp put_if_present(m, _k, nil, _default), do: m
  defp put_if_present(m, k, v, _default), do: Map.put(m, k, v)

  defp err(field, code, message, value),
    do: %{field: field, code: code, message: message, value: value}
end
