defmodule AgentRuntime.Llm.HttpClient.Default do
  @behaviour AgentRuntime.Llm.HttpClient

  @impl true
  def post(url, headers, body, http_opts, opts) do
    request = {url, headers, ~c"application/json", body}
    :httpc.request(:post, request, http_opts, opts)
  end
end
