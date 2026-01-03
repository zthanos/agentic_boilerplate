defmodule AgentCore.Tools do
  @moduledoc """
  Domain module for Tools.

  A Tool represents a capability that can be invoked during LLM interactions.
  This module contains the pure domain logic for tools, including specification
  management and registry operations.
  """

  alias AgentCore.Tools.{Spec, Registry}

  @type tool_id :: String.t()
  @type tool_input :: map()
  @type tool_output :: map()
  @type tool_error :: term()

  @doc """
  Creates a new tool specification.

  ## Examples

      iex> AgentCore.Tools.new_spec("web.search",
      ...>   name: "Web Search",
      ...>   description: "Search the web for information"
      ...> )
      %AgentCore.Tools.Spec{id: "web.search", ...}
  """
  @spec new_spec(tool_id(), keyword()) :: Spec.t()
  def new_spec(id, opts \\ []) do
    Spec.new(id, opts)
  end

  @doc """
  Normalizes a list of tools to canonical specifications.

  ## Examples

      iex> AgentCore.Tools.normalize_tools([:web_search, "files.read"])
      {:ok, [%AgentCore.Tools.Spec{id: "web.search"}, %AgentCore.Tools.Spec{id: "files.read"}]}
  """
  @spec normalize_tools(Registry.tool_input(), Registry.normalize_opts()) ::
          {:ok, [Spec.t()]} | {:error, term()}
  def normalize_tools(input, opts \\ []) do
    Registry.normalize_tools(input, opts)
  end

  @doc """
  Gets all known tool IDs.
  """
  @spec known_tool_ids() :: [tool_id()]
  def known_tool_ids do
    Registry.known_ids()
  end

  @doc """
  Checks if a tool ID is known in the registry.
  """
  @spec known_tool?(tool_id()) :: boolean()
  def known_tool?(id) do
    Registry.known?(id)
  end

  @doc """
  Resolves a tool alias to its canonical ID.
  """
  @spec resolve_tool_alias(tool_id()) :: tool_id()
  def resolve_tool_alias(id) do
    Registry.resolve_alias(id)
  end

  @doc """
  Fetches a tool specification by ID.
  """
  @spec fetch_tool_spec(tool_id()) :: {:ok, Spec.t()} | :error
  def fetch_tool_spec(id) do
    Registry.fetch(id)
  end

  @doc """
  Validates that a tool specification is well-formed.
  """
  @spec validate_spec(Spec.t()) :: :ok | {:error, term()}
  def validate_spec(%Spec{} = spec) do
    cond do
      is_nil(spec.id) or spec.id == "" ->
        {:error, :missing_id}

      not is_binary(spec.id) ->
        {:error, :invalid_id_type}

      not is_map(spec.params_schema) ->
        {:error, :invalid_params_schema}

      not is_map(spec.compatibility) ->
        {:error, :invalid_compatibility}

      not is_map(spec.flags) ->
        {:error, :invalid_flags}

      true ->
        :ok
    end
  end

  @doc """
  Checks if a tool is compatible with a given provider.
  """
  @spec compatible_with_provider?(Spec.t(), atom()) :: boolean()
  def compatible_with_provider?(%Spec{compatibility: compatibility}, provider) do
    Map.get(compatibility, provider, false)
  end

  @doc """
  Checks if a tool has a specific flag set.
  """
  @spec has_flag?(Spec.t(), atom()) :: boolean()
  def has_flag?(%Spec{flags: flags}, flag) do
    Map.get(flags, flag, false)
  end

  @doc """
  Gets the parameter schema for a tool.
  """
  @spec params_schema(Spec.t()) :: map()
  def params_schema(%Spec{params_schema: schema}), do: schema

  @doc """
  Validates tool input against the tool's parameter schema.

  This is a basic validation - more sophisticated schema validation
  would be implemented by the runtime layer.
  """
  @spec validate_input(Spec.t(), tool_input()) :: :ok | {:error, term()}
  def validate_input(%Spec{params_schema: schema}, input) when is_map(input) do
    case schema do
      %{required: required_fields} when is_list(required_fields) ->
        validate_required_fields(input, required_fields)

      _ ->
        :ok
    end
  end

  @doc """
  Creates a canonical tool ID from various input formats.
  """
  @spec canonical_id(atom() | String.t()) :: String.t()
  def canonical_id(id), do: Spec.canonical_id(id)

  # Private helpers

  defp validate_required_fields(input, required_fields) do
    missing_fields =
      required_fields
      |> Enum.reject(&Map.has_key?(input, &1))

    case missing_fields do
      [] -> :ok
      fields -> {:error, {:missing_required_fields, fields}}
    end
  end
end
