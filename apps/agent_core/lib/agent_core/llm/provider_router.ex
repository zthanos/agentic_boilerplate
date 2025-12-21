defmodule AgentCore.Llm.ProviderRouter do
  @moduledoc """
  Maps provider atoms to adapter modules.

  Keep this config-driven so swapping providers is a config change.
  """

  @spec pick(atom()) :: module()
  def pick(provider) when is_atom(provider) do
    mapping = Application.get_env(:agent_core, __MODULE__, [])

    case Keyword.fetch(mapping, provider) do
      {:ok, mod} when is_atom(mod) -> mod
      :error -> raise ArgumentError, "No provider adapter configured for #{inspect(provider)}"
    end
  end
end
