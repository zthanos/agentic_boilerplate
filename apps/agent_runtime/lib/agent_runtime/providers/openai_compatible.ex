defmodule AgentRuntime.Llm.Providers.OpenAICompatible do
  @moduledoc """
  OpenAI-compatible HTTP provider adapter.

  Works with LM Studio, OpenAI, and other OpenAI-compatible endpoints
  by changing OPENAI_COMPAT_BASE_URL / OPENAI_COMPAT_API_KEY.

  No streaming, no tools execution (out of scope).
  """

  @behaviour AgentCore.Llm.ProviderAdapter

  alias AgentCore.Llm.{ProviderRequest, ProviderResponse}
  alias AgentRuntime.Llm.ConnectionResolver

  @chat_path "/v1/chat/completions"
  @completion_path "/v1/completions"

  @impl true
  def call(%ProviderRequest{} = req) do
    conn = ConnectionResolver.openai_compatible()

    with {:ok, {path, payload}} <- build_request(req),
         {:ok, body} <- json_encode(payload),
         {:ok, %{} = resp_map} <- http_post(conn.base_url <> path, body, conn.api_key, conn.timeout_ms),
         {:ok, provider_resp} <- parse_response(req, resp_map) do
      {:ok, provider_resp}
    end
  end

  # -------------------------
  # Build request
  # -------------------------

  defp build_request(%ProviderRequest{invocation: inv, input: %{type: :chat, messages: msgs}}) do
    {:ok,
     {@chat_path,
      %{
        "model" => to_string(inv.model),
        "messages" => Enum.map(msgs || [], &normalize_chat_message/1),
        "temperature" => get_in(inv.generation || %{}, [:temperature]),
        "top_p" => get_in(inv.generation || %{}, [:top_p]),
        "max_tokens" => get_in(inv.generation || %{}, [:max_output_tokens])
      }
      |> drop_nil_values()}}
  end

  defp build_request(%ProviderRequest{invocation: inv, input: %{type: :completion, prompt: prompt}}) do
    {:ok,
     {@completion_path,
      %{
        "model" => to_string(inv.model),
        "prompt" => prompt,
        "temperature" => get_in(inv.generation || %{}, [:temperature]),
        "top_p" => get_in(inv.generation || %{}, [:top_p]),
        "max_tokens" => get_in(inv.generation || %{}, [:max_output_tokens])
      }
      |> drop_nil_values()}}
  end

  defp build_request(%ProviderRequest{input: other}),
    do: {:error, {:unsupported_input, other}}

  defp normalize_chat_message(m) do
    %{
      "role" => m.role |> to_string(),
      "content" => Map.get(m, :content)
    }
    |> maybe_put("name", Map.get(m, :name))
    |> maybe_put("tool_call_id", Map.get(m, :tool_call_id))
  end

  defp maybe_put(map, _k, nil), do: map
  defp maybe_put(map, k, v), do: Map.put(map, k, v)

  defp drop_nil_values(map) do
    map
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  # -------------------------
  # HTTP (no extra deps)
  # -------------------------

  defp http_post(url, body, api_key, timeout_ms) do
    headers =
      [{"content-type", "application/json"}]
      |> maybe_auth(api_key)

    http_opts = [
      timeout: timeout_ms,
      connect_timeout: min(10_000, timeout_ms)
    ]

    request = {to_charlist(url), headers, ~c"application/json", to_charlist(body)}


    case :httpc.request(:post, request, http_opts, body_format: :binary) do
      {:ok, {{_http, status, _reason}, _resp_headers, resp_body}} when status in 200..299 ->
        json_decode(resp_body)

      {:ok, {{_http, status, _reason}, _resp_headers, resp_body}} ->
        {:error, {:http_error, status, resp_body}}

      {:error, reason} ->
        {:error, {:http_error, reason}}
    end
  end

  defp maybe_auth(headers, nil), do: headers
  defp maybe_auth(headers, ""), do: headers
  defp maybe_auth(headers, api_key), do: [{"authorization", "Bearer " <> api_key} | headers]

  defp json_encode(map) do
    {:ok, Jason.encode!(map)}
  rescue
    e -> {:error, {:json_encode_failed, e}}
  end

  defp json_decode(bin) when is_binary(bin) do
    {:ok, Jason.decode!(bin)}
  rescue
    e -> {:error, {:json_decode_failed, e, bin}}
  end

  # -------------------------
  # Parse response
  # -------------------------

  defp parse_response(%ProviderRequest{input: %{type: :chat}}, %{"choices" => [c | _]} = raw) do
    text =
      c
      |> Map.get("message", %{})
      |> Map.get("content", "")
      |> to_string()

    usage = Map.get(raw, "usage", %{})
    {:ok, ProviderResponse.ok(text, raw: raw, usage: usage, finish_reason: c["finish_reason"])}
  end

  defp parse_response(%ProviderRequest{input: %{type: :completion}}, %{"choices" => [c | _]} = raw) do
    text = c |> Map.get("text", "") |> to_string()
    usage = Map.get(raw, "usage", %{})
    {:ok, ProviderResponse.ok(text, raw: raw, usage: usage, finish_reason: c["finish_reason"])}
  end

  defp parse_response(_req, raw),
    do: {:error, {:unexpected_response_shape, raw}}
end
