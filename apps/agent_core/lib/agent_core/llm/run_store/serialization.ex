defmodule AgentCore.RunStore.Serialization do
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

  defp is_scalar(v) when is_binary(v) or is_number(v) or is_boolean(v) or is_nil(v), do: true
  defp is_scalar(_), do: false

  defp is_map_with_id(%{} = m), do: is_binary(Map.get(m, "id"))
  defp is_map_with_id(_), do: false
end
