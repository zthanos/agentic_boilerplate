defmodule AgentRuntime.Llm.ProviderRouter do
  @moduledoc """
  Deterministic provider routing based on InvocationConfig.provider.
  """

    @spec route(atom()) :: {:ok, module()} | {:error, term()}
    def route(:fake), do: {:ok, AgentCore.Llm.Providers.FakeProvider}
    def route(:openai_compatible), do: {:ok, AgentRuntime.Llm.Providers.OpenAICompatible}
    def route(provider), do: {:error, {:unsupported_provider, provider}}
  end
