defmodule AgentRuntime.Llm.ProviderRouter do
  @moduledoc """
  Deterministic provider routing based on InvocationConfig.provider.

  Supports test/dev overrides via config.
  """

  @type provider :: atom()

  @spec route(provider()) :: {:ok, module()} | {:error, term()}
  def route(provider) when is_atom(provider) do
    case override_for(provider) do
      {:ok, mod} when is_atom(mod) -> {:ok, mod}  # Δεν ταιριάζει με :none
      _ -> default_route(provider)                 # Ταιριάζει με :none
    end
  end

  defp default_route(:fake), do: {:ok, AgentCore.Llm.Providers.FakeProvider}
  defp default_route(:openai_compatible), do: {:ok, AgentRuntime.Llm.Providers.OpenAICompatible}
  defp default_route(provider), do: {:error, {:unsupported_provider, provider}}

  defp override_for(provider) do
    overrides =
      Application.get_env(:agent_runtime, __MODULE__, [])
      |> Keyword.get(:overrides, %{})

    case Map.get(overrides, provider) do
      mod when is_atom(mod) and not is_nil(mod) -> {:ok, mod}
      _ -> :none
    end
  end
end
