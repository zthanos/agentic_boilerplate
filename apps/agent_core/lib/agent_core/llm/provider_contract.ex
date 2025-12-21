defmodule AgentCore.Llm.ProviderContract do
  @moduledoc "Builds canonical ProviderRequest from InvocationConfig + input."

  alias AgentCore.Llm.{InvocationConfig, ProviderRequest}

  @spec build_request(InvocationConfig.t(), map()) :: ProviderRequest.t()
  def build_request(%InvocationConfig{} = cfg, input) when is_map(input) do
    ProviderRequest.new(
      cfg,
      normalize_input!(input),
      Map.get(cfg, :tools, []),
      %{
        fingerprint: Map.get(cfg, :fingerprint),
        trace_id: Map.get(cfg, :trace_id)
      }
    )
  end

  defp normalize_input!(%{type: :chat, messages: msgs} = input) when is_list(msgs) do
    Enum.each(msgs, &validate_message!/1)
    input
  end

  defp normalize_input!(%{type: :completion, prompt: prompt} = input) when is_binary(prompt) do
    input
  end

  defp normalize_input!(other) do
    raise ArgumentError, "Invalid LLM input shape: #{inspect(other)}"
  end

  defp validate_message!(%{role: role} = _msg)
       when role in [:system, :user, :assistant, :tool],
       do: :ok

  defp validate_message!(other),
    do: raise(ArgumentError, "Invalid chat message: #{inspect(other)}")
end
