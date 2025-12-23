defmodule AgentRuntime.Llm.Providers.OpenAICompatibleModelResolverTest do
  use ExUnit.Case, async: false

  alias AgentRuntime.Llm.ModelResolver

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
    # Inject fake http client
    Application.put_env(:agent_runtime, :llm_http_client, FakeHttp)

    # Configure model mapping
    Application.put_env(:agent_runtime, ModelResolver,
      openai_compatible: %{local: "lmstudio-model"}
    )

    # ProviderConfig env (so base_url is deterministic)
    System.put_env("OPENAI_BASE_URL", "http://example.local/v1")
    System.delete_env("OPENAI_API_KEY")

    on_exit(fn ->
      Application.delete_env(:agent_runtime, :llm_http_client)
      Application.delete_env(:agent_runtime, ModelResolver)
      System.delete_env("OPENAI_BASE_URL")
      System.delete_env("OPENAI_API_KEY")
    end)

    :ok
  end

  test "uses resolved model in request payload" do
    req = %AgentCore.Llm.ProviderRequest{
      invocation: %{provider: :openai_compatible, model: :local, generation: %{}},
      input: %{type: :chat, messages: [%{role: :user, content: "hi"}]},
      tools: [],
      metadata: %{}
    }

    assert {:ok, _} = AgentRuntime.Llm.Providers.OpenAICompatible.call(req)

    assert_received {:post, _url, _headers, body, _http_opts}

    payload = body |> to_string() |> Jason.decode!()
    assert payload["model"] == "lmstudio-model"
  end
end
