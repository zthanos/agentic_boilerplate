defmodule AgentRuntime.Llm.ModelResolver do
  @moduledoc """
  Resolves a domain model reference (atom/string) to a provider-specific model id (string).

  Runtime-only: driven by application config (and optionally env in the future).
  """

  @type provider :: atom()
  @type model_ref :: atom() | String.t()

  @spec resolve(provider(), model_ref()) :: String.t()
  def resolve(_provider, model) when is_binary(model) and byte_size(model) > 0, do: model

  def resolve(provider, model) when is_atom(provider) and is_atom(model) do
    mapping =
      Application.get_env(:agent_runtime, __MODULE__, [])
      |> Keyword.get(provider, %{})

    Map.get(mapping, model, Atom.to_string(model))
  end

  def resolve(_provider, model) when is_atom(model), do: Atom.to_string(model)
end
