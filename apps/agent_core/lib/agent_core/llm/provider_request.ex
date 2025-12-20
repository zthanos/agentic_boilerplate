defmodule AgentCore.Llm.ProviderRequest do
  @moduledoc """
  Provider-agnostic request builder from InvocationConfig.

  Produces a normalized request map that provider-specific clients can translate
  to their wire format.
  """

  alias AgentCore.Llm.InvocationConfig

  @spec build(InvocationConfig.t(), map()) :: map()
  def build(%InvocationConfig{} = cfg, prompt) when is_map(prompt) do
    %{
      provider: cfg.provider,
      model: cfg.model,
      # generation params
      generation: cfg.generation,
      # IMPORTANT: single source-of-truth for stop
      stop: cfg.stop_list,
      # tool hints (if supported)
      tools: cfg.tools,
      prompt: prompt
    }
    |> drop_nil_or_empty()
  end

  defp drop_nil_or_empty(map) do
    map
    |> Enum.reject(fn
      {_k, nil} -> true
      {_k, []} -> true
      {_k, %{}} -> true
      _ -> false
    end)
    |> Map.new()
  end
end
