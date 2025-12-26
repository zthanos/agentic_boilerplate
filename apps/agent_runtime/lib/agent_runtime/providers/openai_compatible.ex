defmodule AgentRuntime.Llm.Providers.OpenAICompatible do
  @moduledoc """
  OpenAI-compatible HTTP provider adapter.

  Works with LM Studio, OpenAI, and other OpenAI-compatible endpoints
  by changing OPENAI_COMPAT_BASE_URL / OPENAI_COMPAT_API_KEY.

  No streaming, no tools execution (out of scope).
  """

  @behaviour AgentCore.Llm.ProviderAdapter

  alias AgentCore.Llm.{ProviderRequest, ProviderResponse}
  alias AgentRuntime.Llm.ModelResolver
  alias AgentRuntime.Llm.HttpClient.FinchClient

  @chat_path "/chat/completions"
  @completion_path "/completions"
  alias AgentRuntime.Llm.ProviderConfig

  @impl true
  def call(%ProviderRequest{} = req) do
    cfg = ProviderConfig.openai_compatible()

    with {:ok, {path, payload}} <- build_request(req),
         {:ok, body} <- json_encode(payload),
         {:ok, %{} = resp_map} <-
           http_post(
             cfg.base_url <> path,
             body,
             cfg.api_key,
             cfg.timeout_ms,
             cfg.connect_timeout_ms
           ),
         {:ok, provider_resp} <- parse_response(req, resp_map) do
      {:ok, provider_resp}
    end
  end

  # -------------------------
  # Build request
  # -------------------------

  defp build_request(%ProviderRequest{invocation: inv, input: %{type: :chat, messages: msgs}}) do
    provider = Map.get(inv, :provider, :openai_compatible)

    {:ok,
     {@chat_path,
      %{
        "model" => ModelResolver.resolve(provider, inv.model),
        "messages" => Enum.map(msgs || [], &normalize_chat_message/1),
        "temperature" => get_in(inv.generation || %{}, [:temperature]),
        "top_p" => get_in(inv.generation || %{}, [:top_p]),
        "max_tokens" => get_in(inv.generation || %{}, [:max_output_tokens])
      }
      |> drop_nil_values()}}
  end

  defp build_request(%ProviderRequest{
         invocation: inv,
         input: %{type: :completion, prompt: prompt}
       }) do
    {:ok,
     {@completion_path,
      %{
        "model" => ModelResolver.resolve(inv.provider, inv.model),
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
  # Stream support
  # -------------------------
  @impl false
  def stream(%ProviderRequest{} = req, on_chunk) when is_function(on_chunk, 1) do
    cfg = ProviderConfig.openai_compatible()

    with {:ok, {path, payload}} <- build_stream_request(req),
         {:ok, body} <- json_encode(payload),
         {:ok,
          %{full_text: full_text, usage: usage, raw_last: raw_last, finish_reason: finish_reason}} <-
           http_post_stream(cfg.base_url <> path, body, cfg.api_key, cfg.timeout_ms, on_chunk) do
      {:ok,
       ProviderResponse.ok(full_text,
         raw: raw_last,
         usage: usage || %{},
         finish_reason: finish_reason
       )}
    end
  end

  defp build_stream_request(%ProviderRequest{
         invocation: inv,
         input: %{type: :chat, messages: msgs}
       }) do
    provider = Map.get(inv, :provider, :openai_compatible)

    {:ok,
     {@chat_path,
      %{
        "model" => ModelResolver.resolve(provider, inv.model),
        "messages" => Enum.map(msgs || [], &normalize_chat_message/1),
        "temperature" => get_in(inv.generation || %{}, [:temperature]),
        "top_p" => get_in(inv.generation || %{}, [:top_p]),
        "max_tokens" => get_in(inv.generation || %{}, [:max_output_tokens]),
        "stream" => true
      }
      |> drop_nil_values()}}
  end

  defp build_stream_request(%ProviderRequest{input: other}),
    do: {:error, {:unsupported_stream_input, other}}

  defp http_post_stream(url, body, api_key, timeout_ms, on_chunk) do
    headers =
      [
        {"content-type", "application/json"},
        {"accept", "text/event-stream"}
      ]
      |> maybe_auth(api_key)

    req = Finch.build(:post, url, headers, body)

    acc0 = %{
      buf: "",
      full: "",
      raw_last: nil,
      usage: nil,
      finish_reason: nil
    }

    fun = fn
      {:status, status}, acc when status in 200..299 ->
        acc

      {:status, status}, _acc ->
        throw({:http_error, status})

      {:headers, _headers}, acc ->
        acc

      {:data, chunk}, acc ->
        chunk_bin = IO.iodata_to_binary(chunk)
        stream_accumulate(acc, chunk_bin, on_chunk)
    end

    try do
      with {:ok, acc} <-
             Finch.stream(req, AgentRuntimeFinch, acc0, fun, receive_timeout: timeout_ms) do
        {:ok,
         %{
           full_text: acc.full,
           usage: acc.usage,
           raw_last: acc.raw_last,
           finish_reason: acc.finish_reason
         }}
      end
    catch
      {:http_error, status} ->
        {:error, {:http_error, status}}

      {:stream_parse_error, reason} ->
        {:error, {:stream_parse_error, reason}}

      other ->
        {:error, other}
    end
  end

  defp stream_accumulate(acc, chunk, on_chunk) do
    buf = acc.buf <> chunk
    {frames, rest} = split_sse_frames(buf)

    Enum.reduce(frames, %{acc | buf: rest}, fn frame, acc2 ->
      handle_sse_frame(frame, acc2, on_chunk)
    end)
  end

  defp split_sse_frames(buf) do
    parts = String.split(buf, "\n\n", trim: false)

    case parts do
      [] ->
        {[], ""}

      [_only] ->
        {[], buf}

      _ ->
        {Enum.slice(parts, 0, length(parts) - 1), List.last(parts)}
    end
  end

  defp handle_sse_frame(frame, acc, on_chunk) do
    data_lines =
      frame
      |> String.split("\n")
      |> Enum.filter(&String.starts_with?(&1, "data:"))

    Enum.reduce(data_lines, acc, fn line, acc2 ->
      data = line |> String.trim_leading("data:") |> String.trim()

      cond do
        data == "" ->
          acc2

        data == "[DONE]" ->
          acc2

        true ->
          case Jason.decode(data) do
            {:ok, raw} ->
              {token, finish_reason, usage} = extract_stream_fields(raw)

              acc2
              |> maybe_emit_token(token, on_chunk)
              |> update_finish_reason(finish_reason)
              |> update_usage(usage)
              |> Map.put(:raw_last, raw)

            {:error, err} ->
              throw({:stream_parse_error, err})
          end
      end
    end)
  end

  defp extract_stream_fields(%{"choices" => [c | _]} = raw) do
    token =
      c
      |> Map.get("delta", %{})
      |> Map.get("content", "")

    finish_reason = Map.get(c, "finish_reason")
    usage = Map.get(raw, "usage")
    {to_string(token || ""), finish_reason, usage}
  end

  defp extract_stream_fields(_raw), do: {"", nil, nil}

  defp maybe_emit_token(acc, "", _on_chunk), do: acc

  defp maybe_emit_token(acc, token, on_chunk) do
    _ = on_chunk.(token)
    %{acc | full: acc.full <> token}
  end

  defp update_finish_reason(acc, nil), do: acc
  defp update_finish_reason(acc, fr), do: %{acc | finish_reason: fr}

  defp update_usage(acc, nil), do: acc
  defp update_usage(acc, usage), do: %{acc | usage: usage}

  # -------------------------
  # HTTP (no extra deps)
  # -------------------------
  defp http_post(url, body, api_key, timeout_ms, _connect_timeout_ms) do
    headers =
      [
        {"content-type", "application/json"}
      ]
      |> maybe_auth(api_key)

    with {:ok, resp_body} <-
           FinchClient.post_json(
             url,
             body,
             headers,
             receive_timeout: timeout_ms
           ),
         {:ok, %{} = resp_map} <- json_decode(resp_body) do
      {:ok, resp_map}
    end
  end

  # defp http_post(url, body, api_key, timeout_ms, connect_timeout_ms) do
  #   headers =
  #     [{~c"content-type", ~c"application/json"},
  #     {~c"connection", ~c"close"}]
  #     |> maybe_auth(api_key)

  #   http_opts = [
  #     timeout: timeout_ms,
  #     connect_timeout: connect_timeout_ms
  #   ]

  #   case http_client().post(
  #          to_charlist(url),
  #          headers,
  #          to_charlist(body),
  #          http_opts,
  #          [body_format: :binary]
  #        ) do
  #     {:ok, {{_http, status, _reason}, _resp_headers, resp_body}} when status in 200..299 ->
  #       json_decode(resp_body)

  #     {:ok, {{_http, status, _reason}, _resp_headers, resp_body}} ->
  #       {:error, {:http_error, status, resp_body}}

  #     {:error, reason} ->
  #       {:error, {:http_error, reason}}
  #   end
  # end

  # defp http_client do
  #   Application.get_env(:agent_runtime, :llm_http_client, AgentRuntime.Llm.HttpClient.Default)
  # end

  defp maybe_auth(headers, nil), do: headers
  defp maybe_auth(headers, ""), do: headers

  defp maybe_auth(headers, api_key),
    do: [{"authorization", "Bearer " <> api_key} | headers]

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

  defp parse_response(
         %ProviderRequest{input: %{type: :completion}},
         %{"choices" => [c | _]} = raw
       ) do
    text = c |> Map.get("text", "") |> to_string()
    usage = Map.get(raw, "usage", %{})
    {:ok, ProviderResponse.ok(text, raw: raw, usage: usage, finish_reason: c["finish_reason"])}
  end

  defp parse_response(_req, raw),
    do: {:error, {:unexpected_response_shape, raw}}
end
