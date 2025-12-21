defmodule AgentCore.Llm.Tools.Registry do
  @moduledoc """
  Known-tools registry + deterministic normalization.

  This module is provider-agnostic. Provider adapters map ToolSpec -> provider tool format.

  Key semantics:
  - Tools are canonicalized to ToolSpec with string `id`
  - Aliases resolve to canonical ids
  - :__clear__ (in list) resets tools; only items after the last :__clear__ are kept
  - Dedup keeps first occurrence
  - Ordering default: sorted by id (deterministic)
  """

  alias AgentCore.Llm.Tools.ToolSpec

  @type tool_id :: String.t()
  @type tool_item :: atom() | String.t() | ToolSpec.t() | map()
  @type tool_input :: nil | :__clear__ | [tool_item()]

  @type normalize_opts :: [
          allowed: :all | [tool_id()],
          allow_unknown?: boolean(),
          ordering: :sorted_ids | :stable
        ]

  # ------------------------------------------
  # Known tools
  # ------------------------------------------
  # Προσαρμόζεις την λίστα στο domain σου.
  @known_tools [
    ToolSpec.new("web.search",
      name: "Web Search",
      description: "Search the web",
      compatibility: %{openai: true, azure_openai: true}
    ),
    ToolSpec.new("files.read",
      name: "Files Read",
      description: "Read file contents from storage",
      compatibility: %{openai: true, azure_openai: true}
    ),
    ToolSpec.new("math.eval",
      name: "Math Eval",
      description: "Evaluate basic expressions",
      compatibility: %{openai: true, azure_openai: true}
    )
  ]

  @known_by_id Map.new(@known_tools, fn %ToolSpec{id: id} = spec -> {id, spec} end)

  # Aliases -> canonical id
  @aliases %{
    "web" => "web.search",
    "search" => "web.search",
    "web_search" => "web.search",
    "files" => "files.read",
    "file_read" => "files.read",
    "read_file" => "files.read",
    "calc" => "math.eval",
    "calculator" => "math.eval"
  }

  @spec known_ids() :: [tool_id()]
  def known_ids do
    @known_by_id |> Map.keys() |> Enum.sort()
  end

  @spec known?(tool_id()) :: boolean()
  def known?(id) when is_binary(id), do: Map.has_key?(@known_by_id, id)

  @spec resolve_alias(tool_id()) :: tool_id()
  def resolve_alias(id) when is_binary(id) do
    trimmed = String.trim(id)

    cond do
      known?(trimmed) ->
        trimmed

      true ->
        key = String.downcase(trimmed)
        Map.get(@aliases, key, trimmed)
    end
  end

  @spec fetch(tool_id()) :: {:ok, ToolSpec.t()} | :error
  def fetch(id) when is_binary(id) do
    Map.fetch(@known_by_id, id)
    |> case do
      {:ok, spec} -> {:ok, spec}
      :error -> :error
    end
  end

  @doc """
  Normalizes tools to a canonical list of ToolSpec (deterministic).

  Input accepts:
  - nil -> []
  - :__clear__ -> []
  - list of atoms/strings/ToolSpec/maps
  - list may include :__clear__ which resets tools (keep suffix after last clear)

  Options:
  - allowed: :all (default) or list of allowed canonical ids
  - allow_unknown?: false (default) rejects unknown tool ids
  - ordering: :sorted_ids (default) or :stable (keeps insertion order after dedup)
  """
  @spec normalize_tools(tool_input(), normalize_opts()) ::
          {:ok, [ToolSpec.t()]} | {:error, term()}
  def normalize_tools(input, opts \\ []) do
    allow_unknown? = Keyword.get(opts, :allow_unknown?, false)
    ordering = Keyword.get(opts, :ordering, :sorted_ids)
    allowed_opt = Keyword.get(opts, :allowed, :all)

    list =
      case input do
        nil -> []
        :__clear__ -> []
        l when is_list(l) -> l
        other -> other
      end

    with true <- is_list(list) or {:error, {:invalid_tools_type, list}},
         list <- apply_clear_semantics(list),
         {:ok, specs} <- parse_items(list),
         specs <- Enum.map(specs, &resolve_id/1),
         :ok <- validate_specs(specs, allowed_opt, allow_unknown?),
         specs <- dedup_keep_first(specs),
         specs <- apply_ordering(specs, ordering) do
      {:ok, specs}
    end
  end

  # -----------------------------
  # Internals
  # -----------------------------

  # If list contains :__clear__, keep only suffix after last occurrence.
  defp apply_clear_semantics(list) do
    idx =
      list
      |> Enum.with_index()
      |> Enum.filter(fn {v, _i} -> v == :__clear__ end)
      |> case do
        [] -> nil
        clears -> clears |> List.last() |> elem(1)
      end

    if is_integer(idx) do
      Enum.drop(list, idx + 1)
    else
      list
    end
  end

  defp parse_items(list) do
    parsed =
      Enum.map(list, fn
        %ToolSpec{} = spec ->
          {:ok, spec}

        %{"id" => id} = m when is_binary(id) ->
          {:ok, ToolSpec.new(id, name: m["name"], description: m["description"])}

        %{id: id} = m when is_binary(id) ->
          {:ok, ToolSpec.new(id, name: Map.get(m, :name), description: Map.get(m, :description))}

        id when is_atom(id) or is_binary(id) ->
          {:ok, ToolSpec.new(ToolSpec.canonical_id(id))}

        other ->
          {:error, {:invalid_tool_item, other}}
      end)

    case Enum.find(parsed, &match?({:error, _}, &1)) do
      nil -> {:ok, Enum.map(parsed, fn {:ok, v} -> v end)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_id(%ToolSpec{id: id} = spec) do
    %{spec | id: resolve_alias(id)}
  end

  defp validate_specs(specs, allowed_opt, allow_unknown?) do
    allowed_ids =
      case allowed_opt do
        :all -> MapSet.new(known_ids())
        ids when is_list(ids) -> MapSet.new(Enum.map(ids, &String.trim/1))
      end

    bad =
      Enum.find(specs, fn %ToolSpec{id: id} ->
        cond do
          allow_unknown? ->
            # If unknowns are allowed, only restrict if known but disallowed (optional stance).
            known?(id) and not MapSet.member?(allowed_ids, id)

          true ->
            # Strict: must be known and allowed
            (not known?(id)) or (not MapSet.member?(allowed_ids, id))
        end
      end)

    case bad do
      nil ->
        :ok

      %ToolSpec{id: id} ->
        cond do
          not known?(id) and not allow_unknown? -> {:error, {:unknown_tool, id}}
          true -> {:error, {:tool_not_allowed, id}}
        end
    end
  end

  defp dedup_keep_first(specs) do
    {acc, _seen} =
      Enum.reduce(specs, {[], MapSet.new()}, fn %ToolSpec{id: id} = spec, {a, seen} ->
        if MapSet.member?(seen, id) do
          {a, seen}
        else
          {[spec | a], MapSet.put(seen, id)}
        end
      end)

    Enum.reverse(acc)
  end

  defp apply_ordering(specs, :sorted_ids), do: Enum.sort_by(specs, & &1.id)
  defp apply_ordering(specs, :stable), do: specs
  defp apply_ordering(_specs, other), do: raise(ArgumentError, "Invalid ordering: #{inspect(other)}")

end
