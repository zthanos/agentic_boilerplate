defmodule AgentRuntime.Llm.Providers.OpenAICompatibleTest do
  use ExUnit.Case, async: false

  defmodule FakeHttp do
    @behaviour AgentRuntime.Llm.HttpClient

    @impl true
    def post(url, headers, body, http_opts, _opts) do
      send(self(), {:post, url, headers, body, http_opts})

      resp_body =
        ~s({"choices":[{"message":{"content":"ok"},"finish_reason":"stop"}],"usage":{"total_tokens":1}})

      {:ok, {{~c"HTTP/1.1", 200, ~c"OK"}, [], resp_body}}
    end

  end

  setup do
    Application.put_env(:agent_runtime, :llm_http_client, FakeHttp)
    System.put_env("OPENAI_BASE_URL", "http://example.local/v1")
    System.delete_env("OPENAI_API_KEY")

    on_exit(fn ->
      Application.delete_env(:agent_runtime, :llm_http_client)
      System.delete_env("OPENAI_BASE_URL")
      System.delete_env("OPENAI_API_KEY")
    end)

    :ok
  end

  test "does not add auth header when api_key is nil and uses /v1 base_url once" do
    req = %AgentCore.Llm.ProviderRequest{
      invocation: %{model: :local, generation: %{}},
      input: %{type: :chat, messages: [%{role: :user, content: "hi"}]}
    }
    assert {:ok, _} = AgentRuntime.Llm.Providers.OpenAICompatible.call(req)

    assert_received {:post, url, headers, _body, _http_opts}
    assert to_string(url) == "http://example.local/v1/chat/completions"

    refute Enum.any?(headers, fn {k, _v} ->
             String.downcase(to_string(k)) == "authorization"
           end)
  end
end
