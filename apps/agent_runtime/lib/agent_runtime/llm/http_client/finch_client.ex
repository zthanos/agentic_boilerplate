defmodule AgentRuntime.Llm.HttpClient.FinchClient do
  @moduledoc false

  require Logger

  @finch AgentRuntimeFinch

  def post_json(url, body, headers, opts \\ []) do
    receive_timeout = Keyword.get(opts, :receive_timeout, 60_000)
    pool_timeout = Keyword.get(opts, :pool_timeout, 5_000)

    req =
      Finch.build(
        :post,
        url,
        headers,
        body
      )

    case Finch.request(req, @finch,
           receive_timeout: receive_timeout,
           pool_timeout: pool_timeout
         ) do
      {:ok, %Finch.Response{status: status, body: resp_body}}
      when status in 200..299 ->
        {:ok, resp_body}

      {:ok, %Finch.Response{status: status, body: resp_body}} ->
        {:error, {:http_error, status, resp_body}}

      {:error, reason} ->
        {:error, {:http_error, reason}}
    end
  end

  def http_post_stream(url, body, api_key, timeout_ms, on_chunk) do
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
      done?: false,
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
        acc
        |> stream_accumulate(chunk, on_chunk)
    end

    try do
      acc =
        Finch.stream(req, AgentRuntimeFinch, acc0, fun,
          receive_timeout: timeout_ms
        )

      {:ok, %{full_text: acc.full, usage: acc.usage, raw_last: acc.raw_last, finish_reason: acc.finish_reason}}
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

    acc =
      Enum.reduce(frames, %{acc | buf: rest}, fn frame, acc2 ->
        handle_sse_frame(frame, acc2, on_chunk)
      end)

    acc
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
    # Find "data: ..." lines
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
          %{acc2 | done?: true}

        true ->
          case Jason.decode(data) do
            {:ok, raw} ->
              {token, finish_reason, usage} = extract_stream_fields(raw)

              acc2 =
                acc2
                |> maybe_emit_token(token, on_chunk)
                |> update_finish_reason(finish_reason)
                |> update_usage(usage)
                |> Map.put(:raw_last, raw)

              acc2

            {:error, err} ->
              throw({:stream_parse_error, err})
          end
      end
    end)
  end

  defp extract_stream_fields(%{"choices" => [c | _]} = raw) do
    # OpenAI chat streaming: choices[0].delta.content
    token =
      c
      |> Map.get("delta", %{})
      |> Map.get("content", "")

    finish_reason = Map.get(c, "finish_reason")
    usage = Map.get(raw, "usage") # often nil during stream; may appear at end depending on server
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


  defp maybe_auth(headers, nil), do: headers
  defp maybe_auth(headers, ""), do: headers

  defp maybe_auth(headers, api_key),
    do: [{~c"authorization", to_charlist("Bearer " <> api_key)} | headers]

end
