defmodule AgentRuntime.Providers.Fake do
  @moduledoc """
  Fake provider implementation for testing and development.

  This provider returns deterministic responses without making actual API calls,
  making it useful for testing, development, and CI environments.
  """

  @behaviour AgentCore.Providers.Behavior

  alias AgentCore.Providers.{Request, Response}
  alias AgentCore.Llm.{ProviderRequest, ProviderResponse}

  @impl true
  def execute(%Request{} = req, _config, _opts \\ []) do
    # Generate fake response based on the last user message
    fake_content = generate_fake_response(req.messages)

    choice = %{
      index: 0,
      message: %{
        role: :assistant,
        content: fake_content,
        tool_calls: nil,
        name: nil
      },
      finish_reason: :stop
    }

    usage = %{
      prompt_tokens: count_tokens(req.messages),
      completion_tokens: count_tokens([fake_content]),
      total_tokens: count_tokens(req.messages) + count_tokens([fake_content]),
      cost: 0.0
    }

    response = %Response{
      id: "fake-" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)),
      model: req.model || "fake-model",
      choices: [choice],
      usage: usage,
      created_at: DateTime.utc_now(),
      finish_reason: :stop,
      metadata: %{
        fake: true,
        provider: "fake",
        timestamp: DateTime.utc_now()
      }
    }

    {:ok, response}
  end

  @impl true
  def health_check(_config, _opts \\ []) do
    :ok
  end

  @impl true
  def validate_config(_config) do
    :ok
  end

  @impl true
  def supported_models(_config) do
    {:ok, ["fake-model", "fake-gpt-3.5", "fake-gpt-4", "fake-claude"]}
  end

  @impl true
  def estimate_cost(_request, _config) do
    {:ok, 0.0}
  end

  @impl true
  def transform_request(request, _config) do
    {:ok, Map.from_struct(request)}
  end

  @impl true
  def transform_response(provider_response, _config) do
    # Already in the right format since this is a fake provider
    {:ok, provider_response}
  end

  # Legacy interface for backward compatibility
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

          "FAKE: " <> ((last && last[:content]) || "")
      end

    {:ok,
     ProviderResponse.ok(text,
       raw: %{fake: true, provider: req.invocation.provider},
       usage: %{input_tokens: 0, output_tokens: 0, total_tokens: 0},
       finish_reason: "stop",
       tool_calls: []
     )}
  end

  # Legacy test functions for backward compatibility
  def test_connection(_provider_config) do
    {:ok, %{
      status: :success,
      message: "Fake provider connection test successful",
      response_time_ms: 1,
      details: %{
        fake: true,
        always_available: true
      }
    }}
  end

  def test_authentication(_provider_config) do
    {:ok, %{
      status: :success,
      message: "Fake provider authentication test successful (no auth required)"
    }}
  end

  # Private helper functions
  defp generate_fake_response(messages) when is_list(messages) do
    last_user_message =
      messages
      |> Enum.reverse()
      |> Enum.find(fn msg -> msg[:role] == "user" end)

    case last_user_message do
      %{content: content} when is_binary(content) ->
        "FAKE RESPONSE: I understand you said '#{String.slice(content, 0, 50)}#{if String.length(content) > 50, do: "...", else: ""}'. This is a fake response for testing."
      _ ->
        "FAKE RESPONSE: This is a fake response for testing purposes."
    end
  end

  defp generate_fake_response(_), do: "FAKE RESPONSE: This is a fake response for testing purposes."

  defp count_tokens(messages) when is_list(messages) do
    messages
    |> Enum.map(fn
      %{content: content} when is_binary(content) -> String.length(content)
      content when is_binary(content) -> String.length(content)
      _ -> 0
    end)
    |> Enum.sum()
    |> div(4)  # Rough approximation: 4 characters per token
    |> max(1)
  end

  defp count_tokens(content) when is_binary(content) do
    content |> String.length() |> div(4) |> max(1)
  end

  defp count_tokens(_), do: 1
end
