# apps/agent_web/lib/agent_web/streaming/sse_manager.ex
defmodule AgentWeb.Streaming.SseManager do
  @moduledoc """
  Manages Server-Sent Events (SSE) streaming over HTTP.
  This is a web transport layer concern, handling Plug.Conn and SSE protocol.

  Works with AgentRuntime.Llm.StreamEvent for event definitions.
  """

  alias AgentRuntime.Llm.StreamEvent

  @doc """
  Sets up SSE headers and sends chunked response.
  """
  def setup_sse_conn(conn) do
    conn
    |> Plug.Conn.put_resp_header("content-type", "text/event-stream")
    |> Plug.Conn.put_resp_header("cache-control", "no-cache")
    |> Plug.Conn.put_resp_header("connection", "keep-alive")
    |> Plug.Conn.send_chunked(200)
  end

  @doc """
  Sends an SSE event to the client.
  Returns {:ok, conn} or {:error, reason}.
  """
  def send_event(conn, %StreamEvent{event: event, data: data}) do
    send_event(conn, event, data)
  end

  def send_event(conn, event, data) when is_atom(event) and is_map(data) do
    payload = Jason.encode!(data)

    case Plug.Conn.chunk(conn, "event: #{event}\ndata: #{payload}\n\n") do
      {:ok, conn} -> {:ok, conn}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Main SSE receive loop. Listens for messages from the streaming task
  and forwards them as SSE events to the client.

  Options:
    - timeout: Ping interval in milliseconds (default: 60_000)
  """
  def event_loop(conn, task_ref, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 60_000)
    do_event_loop(conn, task_ref, timeout)
  end

  # Private loop implementation
  defp do_event_loop(conn, task_ref, timeout) do
    receive do
      # Token streaming
      {:sse_token, token} ->
        case send_event(conn, StreamEvent.token(token)) do
          {:ok, conn} -> do_event_loop(conn, task_ref, timeout)
          {:error, _reason} -> conn
        end

      # Successful execution with results
      {:sse_result,
       {:ok,
        %{
          run_id: run_id,
          trace_id: trace_id,
          fingerprint: fp,
          latency_ms: latency,
          response: resp
        }}} ->
        usage = fetch_field(resp, [:usage, "usage"])
        _ = send_event(conn, StreamEvent.done(run_id, trace_id, fp, latency, usage))
        conn

      # Clarification needed
      {:sse_result,
       {:ok,
        %{
          mode: :needs_clarification,
          trace_id: trace_id,
          question: question
        }}} ->
        _ = send_event(conn, StreamEvent.clarify(trace_id, question))
        conn

      # Error result
      {:sse_result,
       {:error,
        %{
          reason: reason,
          run_id: run_id,
          trace_id: trace_id,
          fingerprint: fp,
          latency_ms: latency
        }}} ->
        error = normalize_error(reason)
        _ = send_event(conn, StreamEvent.error(error, run_id, trace_id, fp, latency))
        conn

      # Task completed normally
      {:DOWN, ^task_ref, :process, _pid, :normal} ->
        conn

      {:DOWN, ^task_ref, :process, _pid, :shutdown} ->
        conn

      # Task crashed
      {:DOWN, ^task_ref, :process, _pid, reason} ->
        error = %{
          "message" => "stream_worker_crashed",
          "detail" => inspect(reason)
        }

        _ = send_event(conn, StreamEvent.error(error))
        conn
    after
      timeout ->
        case send_event(conn, StreamEvent.ping()) do
          {:ok, conn} -> do_event_loop(conn, task_ref, timeout)
          {:error, _reason} -> conn
        end
    end
  end

  @doc """
  Executes a streaming task with automatic event forwarding.
  The task function should send messages back to the parent process.

  Returns the connection after streaming completes.
  """
  def stream_with_events(conn, stream_fn) do
    parent = self()

    task =
      Task.async(fn ->
        on_chunk = fn token ->
          send(parent, {:sse_token, token || ""})
          :ok
        end

        result = stream_fn.(on_chunk)
        send(parent, {:sse_result, result})
        :ok
      end)

    case send_event(conn, StreamEvent.open()) do
      {:ok, conn} ->
        event_loop(conn, task.ref)

      {:error, _reason} ->
        Task.shutdown(task, :brutal_kill)
        conn
    end
  end

  # Helper functions

  defp fetch_field(map, keys) when is_list(keys) do
    Enum.reduce_while(keys, nil, fn k, _acc ->
      v =
        cond do
          is_map(map) and is_atom(k) -> Map.get(map, k)
          is_map(map) and is_binary(k) -> Map.get(map, k)
          true -> nil
        end

      if is_nil(v), do: {:cont, nil}, else: {:halt, v}
    end)
  end

  defp normalize_error(%{"message" => _} = m), do: m
  defp normalize_error(%{message: _} = m), do: Map.new(m)
  defp normalize_error(reason) when is_binary(reason), do: %{"message" => reason}
  defp normalize_error(reason), do: %{"message" => inspect(reason)}
end
