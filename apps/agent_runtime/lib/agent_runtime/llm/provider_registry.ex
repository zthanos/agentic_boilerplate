defmodule AgentRuntime.Llm.ProviderRegistry do
  @moduledoc """
  Runtime facade for provider discovery and invocation.

  Wraps ProviderRouter and is the single entry point for resolving adapters.
  """

  alias AgentRuntime.Llm.ProviderRouter

  @type provider :: atom()

  @spec adapter(provider()) :: {:ok, module()} | {:error, term()}
  def adapter(provider) when is_atom(provider) do
    ProviderRouter.route(provider)
  end
end
