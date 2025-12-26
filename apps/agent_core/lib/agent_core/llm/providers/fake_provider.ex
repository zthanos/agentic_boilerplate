defmodule AgentCore.Llm.Providers.FakeProvider do
  @moduledoc "Deterministic provider stub for infra tests and pipeline wiring."

  @behaviour AgentCore.Llm.ProviderAdapter

  alias AgentCore.Llm.{ProviderRequest, ProviderResponse}

  @impl true
  def call(%ProviderRequest{} = req) do
    text =
      case req.input do
        %{type: :completion, prompt: p} ->
          "FAKE: " <> p

        %{type: :chat, messages: msgs} ->
          last =
            msgs
            |> Enum.reverse()
            |> Enum.find(fn m -> m[:role] in [:user, :system] and is_binary(m[:content]) end)

          "FAKE: " <> (last && last[:content] || "")
      end

    {:ok,
     ProviderResponse.ok(text,
       raw: %{fake: true, provider: req.invocation.provider},
       usage: %{input_tokens: 0, output_tokens: 0, total_tokens: 0},
       finish_reason: "stop",
       tool_calls: []
     )}
  end
end
