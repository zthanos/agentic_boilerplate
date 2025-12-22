defmodule AgentCore.Llm.ProviderRoute1r do
  @moduledoc """
  Deterministic provider routing based on InvocationConfig.provider.
  """

  alias AgentCore.Llm.InvocationConfig

  @spec route(InvocationConfig.t()) :: {:ok, module()} | {:error, term()}
  def route(%InvocationConfig{provider: provider}) do
    case provider do
      :fake -> {:ok, AgentCore.Providers.FakeProvider}
      # later:
      # :openai -> {:ok, AgentRuntime.Providers.OpenAI}
      # :ollama -> {:ok, AgentRuntime.Providers.Ollama}
      _ -> {:error, {:unknown_provider, provider}}
    end
  end
end
