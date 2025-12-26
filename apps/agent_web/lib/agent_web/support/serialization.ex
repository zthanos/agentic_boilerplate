defmodule AgentWeb.Support.Serialization do
  @moduledoc """
  Canonical serialization helpers for run snapshots.

  Goal:
  - stable JSON (portable across stores)
  - avoid atom keys in stored JSON
  """

  @spec deep_stringify_keys(term()) :: term()
  def deep_stringify_keys(value) when is_map(value) do
    value
    |> Enum.map(fn {k, v} ->
      {stringify_key(k), deep_stringify_keys(v)}
    end)
    |> Map.new()
  end

  def deep_stringify_keys(value) when is_list(value) do
    Enum.map(value, &deep_stringify_keys/1)
  end

  def deep_stringify_keys(value), do: value

  defp stringify_key(k) when is_binary(k), do: k
  defp stringify_key(k) when is_atom(k), do: Atom.to_string(k)
  defp stringify_key(k), do: to_string(k)

  @doc """
  Optional: deep sort for deterministic JSON diffs.

  - Sorts map keys recursively (by key string)
  - Sorts lists only when list elements are sortable maps with "id" OR scalar values
  - Otherwise keeps list order (important for chat messages, tool ordering, etc.)
  """
  @spec deep_sort(term()) :: term()
  def deep_sort(value) when is_map(value) do
    value
    |> Enum.map(fn {k, v} -> {k, deep_sort(v)} end)
    |> Enum.sort_by(fn {k, _v} -> k end)
    |> Map.new()
  end

  def deep_sort(value) when is_list(value) do
    sorted = Enum.map(value, &deep_sort/1)

    cond do
      Enum.all?(sorted, &is_scalar/1) ->
        Enum.sort(sorted)

      Enum.all?(sorted, &is_map_with_id/1) ->
        Enum.sort_by(sorted, fn m -> Map.get(m, "id") end)

      true ->
        sorted
    end
  end
  def deep_sort(value), do: value

  # Converts a term into a JSON-safe structure:
  # - map keys -> strings
  # - atoms -> strings
  # - DateTime -> ISO8601 string
  # - tuples -> lists
  # - structs -> map (from_struct) then recurse (except DateTime)
  def deep_jsonify(term) do
    cond do
      is_nil(term) or is_boolean(term) or is_number(term) or is_binary(term) ->
        term

      is_atom(term) ->
        Atom.to_string(term)

      is_struct(term, DateTime) ->
        DateTime.to_iso8601(term)

      is_struct(term) ->
        term
        |> Map.from_struct()
        |> deep_jsonify()

      is_map(term) ->
        term
        |> Enum.map(fn {k, v} -> {to_string(k), deep_jsonify(v)} end)
        |> Map.new()

      is_list(term) ->
        Enum.map(term, &deep_jsonify/1)

      is_tuple(term) ->
        term
        |> Tuple.to_list()
        |> deep_jsonify()

      true ->
        # Fallback: stringify anything else (pids, refs, functions, etc.)
        inspect(term)
    end
  end



  defp is_scalar(v) when is_binary(v) or is_number(v) or is_boolean(v) or is_nil(v), do: true
  defp is_scalar(_), do: false

  defp is_map_with_id(%{} = m), do: is_binary(Map.get(m, "id"))
  defp is_map_with_id(_), do: false
end
