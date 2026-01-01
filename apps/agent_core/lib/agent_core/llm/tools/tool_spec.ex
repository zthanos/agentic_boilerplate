defmodule AgentCore.Llm.Tools.ToolSpec do
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

  @spec canonical_id(atom() | String.t()) :: String.t()
  def canonical_id(id) when is_atom(id), do: Atom.to_string(id)
  def canonical_id(id) when is_binary(id), do: String.trim(id)
end
