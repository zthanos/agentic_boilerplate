defmodule AgentCore.Llm.Tools.ToolSpec do
  @moduledoc """
  Canonical, provider-agnostic representation of a tool.

  Provider adapters map ToolSpec -> provider-specific tool format.
  """

  @enforce_keys [:id]
  defstruct [
    :id,                 # canonical string id, e.g. "web.search"
    :name,               # optional display name
    :description,        # optional description
    params_schema: %{},  # optional schema map (JSON-schema-ish)
    compatibility: %{},  # e.g. %{openai: true, azure_openai: true}
    flags: %{}           # e.g. %{experimental: true}
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
