defmodule AgentRuntime.Llm.HttpClient.Httpc do
  @behaviour AgentRuntime.Llm.HttpClient

  @impl true
  def post(url, headers, body, http_opts, _opts) do
    send(self(), {:post, url, headers, body, http_opts})

    resp_body =
      ~s({"choices":[{"message":{"content":"ok"},"finish_reason":"stop"}],"usage":{"total_tokens":1}})

    {:ok, {{~c"HTTP/1.1", 200, ~c"OK"}, [], resp_body}}
  end

end
