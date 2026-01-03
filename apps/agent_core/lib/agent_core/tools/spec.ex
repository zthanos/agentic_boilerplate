defmodule AgentCore.Tools.Spec do
  @moduledoc """
  Canonical, provider-agnostic representation of a tool.

  Provider adapters map ToolSpec -> provider-specific tool format.
  """

  @enforce_keys [:id]
  defstruct [
    # canonical string id, e.g. "web.search"
    :id,
    # optional display name
    :name,
    # optional description
    :description,
    # optional schema map (JSON-schema-ish)
    params_schema: %{},
    # e.g. %{openai: true, azure_openai: true}
    compatibility: %{},
    # e.g. %{experimental: true}
    flags: %{}
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t() | nil,
          description: String.t() | nil,
          params_schema: map(),
          compatibility: map(),
          flags: map()
        }

  @doc """
  Creates a new tool specification.

  ## Examples

      iex> AgentCore.Tools.Spec.new("web.search",
      ...>   name: "Web Search",
      ...>   description: "Search the web for information"
      ...> )
      %AgentCore.Tools.Spec{id: "web.search", ...}
  """
  @spec new(String.t(), keyword()) :: t()
  def new(id, opts \\ []) when is_binary(id) do
    %__MODULE__{
      id: String.trim(id),
      name: Keyword.get(opts, :name),
      description: Keyword.get(opts, :description),
      params_schema: Keyword.get(opts, :params_schema, %{}),
      compatibility: Keyword.get(opts, :compatibility, %{}),
      flags: Keyword.get(opts, :flags, %{})
    }
  end

  @doc """
  Converts various ID formats to canonical string format.
  """
  @spec canonical_id(atom() | String.t()) :: String.t()
  def canonical_id(id) when is_atom(id), do: Atom.to_string(id)
  def canonical_id(id) when is_binary(id), do: String.trim(id)

  @doc """
  Updates a tool specification with new attributes.
  """
  @spec update(t(), keyword()) :: t()
  def update(%__MODULE__{} = spec, opts) do
    Enum.reduce(opts, spec, fn {key, value}, acc ->
      case key do
        :name -> %{acc | name: value}
        :description -> %{acc | description: value}
        :params_schema -> %{acc | params_schema: value}
        :compatibility -> %{acc | compatibility: value}
        :flags -> %{acc | flags: value}
        _ -> acc
      end
    end)
  end

  @doc """
  Merges compatibility settings with existing ones.
  """
  @spec add_compatibility(t(), map()) :: t()
  def add_compatibility(%__MODULE__{} = spec, new_compatibility) when is_map(new_compatibility) do
    %{spec | compatibility: Map.merge(spec.compatibility, new_compatibility)}
  end

  @doc """
  Merges flags with existing ones.
  """
  @spec add_flags(t(), map()) :: t()
  def add_flags(%__MODULE__{} = spec, new_flags) when is_map(new_flags) do
    %{spec | flags: Map.merge(spec.flags, new_flags)}
  end

  @doc """
  Checks if the tool is compatible with a specific provider.
  """
  @spec compatible_with?(t(), atom()) :: boolean()
  def compatible_with?(%__MODULE__{compatibility: compatibility}, provider) do
    Map.get(compatibility, provider, false)
  end

  @doc """
  Checks if the tool has a specific flag set.
  """
  @spec has_flag?(t(), atom()) :: boolean()
  def has_flag?(%__MODULE__{flags: flags}, flag) do
    Map.get(flags, flag, false)
  end

  @doc """
  Converts the tool spec to a map representation.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = spec) do
    Map.from_struct(spec)
  end

  @doc """
  Creates a tool spec from a map representation.
  """
  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(%{"id" => id} = map) when is_binary(id) do
    spec = %__MODULE__{
      id: id,
      name: Map.get(map, "name"),
      description: Map.get(map, "description"),
      params_schema: Map.get(map, "params_schema", %{}),
      compatibility: Map.get(map, "compatibility", %{}),
      flags: Map.get(map, "flags", %{})
    }

    {:ok, spec}
  end

  def from_map(%{id: id} = map) when is_binary(id) do
    spec = %__MODULE__{
      id: id,
      name: Map.get(map, :name),
      description: Map.get(map, :description),
      params_schema: Map.get(map, :params_schema, %{}),
      compatibility: Map.get(map, :compatibility, %{}),
      flags: Map.get(map, :flags, %{})
    }

    {:ok, spec}
  end

  def from_map(_), do: {:error, :missing_id}
end
