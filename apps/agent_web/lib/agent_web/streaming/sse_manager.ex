# apps/agent_web/lib/agent_web/streaming/sse_manager.ex
defmodule AgentWeb.Streaming.SseManager do
  @moduledoc """
  Manages Server-Sent Events (SSE) streaming over HTTP.

  Handles two types of events:
  1. Workflow step events - Progress through workflow nodes (from Workflow Engine)
  2. LLM token events - Streaming text content (from LLM Service)

  Works with AgentRuntime.Llm.StreamEvent for event definitions.
  """

  alias AgentRuntime.Llm.StreamEvent

  require Logger

  @doc """
  Sets up SSE headers and sends chunked response.
  """
  def setup_sse_conn(conn) do
    conn
    |> Plug.Conn.put_resp_header("content-type", "text/event-stream; charset=utf-8")
    |> Plug.Conn.put_resp_header("cache-control", "no-cache, no-transform")
    |> Plug.Conn.put_resp_header("connection", "keep-alive")
    |> Plug.Conn.put_resp_header("x-accel-buffering", "no")
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

  Handles two event types:
  - {:sse_token, token} - LLM streaming tokens
  - {:sse_step_execution, step_id, phase, meta} - Workflow progress events

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
      # ========================================
      # LLM Token Events (from LLM Service)
      # ========================================
      {:sse_token, token} ->
        case send_event(conn, StreamEvent.token(token)) do
          {:ok, conn} ->
            do_event_loop(conn, task_ref, timeout)

          {:error, _reason} ->
            Task.shutdown(task_ref, :brutal_kill)
            conn
        end

      # ========================================
      # Workflow Step Events (from Workflow Engine)
      # ========================================
      {:sse_step_execution, step_id, phase, meta} ->
        # Convert workflow engine data to StreamEvent format
        step_name = format_step_name(step_id)
        status = phase_to_status(phase)
        opts = build_step_opts(step_id, meta)

        Logger.debug(
          "[SSE] Step event: #{step_name} -> #{status}, opts=#{inspect(opts)}"
        )

        event = StreamEvent.step_execution(step_name, status, opts)

        case send_event(conn, event) do
          {:ok, conn} ->
            do_event_loop(conn, task_ref, timeout)

          {:error, _reason} ->
            Task.shutdown(task_ref, :brutal_kill)
            conn
        end

      # ========================================
      # Execution Result Events
      # ========================================

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
        _ = send_event(conn, StreamEvent.close())
        Process.sleep(10)
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
        _ = send_event(conn, StreamEvent.close())
        Process.sleep(10)
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
        _ = send_event(conn, StreamEvent.close())
        Process.sleep(10)
        conn

      # Task completed normally
      {:DOWN, ^task_ref, :process, _pid, :normal} ->
        _ = send_event(conn, StreamEvent.close())
        Process.sleep(10)
        conn

      {:DOWN, ^task_ref, :process, _pid, :shutdown} ->
        _ = send_event(conn, StreamEvent.close())
        Process.sleep(10)
        conn

      # Task crashed
      {:DOWN, ^task_ref, :process, _pid, reason} ->
        error = %{
          "message" => "stream_worker_crashed",
          "detail" => inspect(reason)
        }

        _ = send_event(conn, StreamEvent.error(error))
        _ = send_event(conn, StreamEvent.close())
        Process.sleep(10)
        conn
    after
      timeout ->
        case send_event(conn, StreamEvent.ping()) do
          {:ok, conn} ->
            do_event_loop(conn, task_ref, timeout)

          {:error, _reason} ->
            Task.shutdown(task_ref, :brutal_kill)
            conn
        end
    end
  end

  @doc """
  Executes a streaming task with automatic event forwarding.

  Creates two callbacks:
  - on_chunk: For LLM token streaming
  - on_workflow_progress: For workflow step progress

  Returns the connection after streaming completes.
  """
  def stream_with_events(conn, stream_fn) do
    parent = self()

    Logger.info("[SSE] Starting stream_with_events")

    task =
      Task.async(fn ->
        Logger.info("[SSE Task] Task started")

        # Callback for LLM token streaming
        on_chunk = fn token ->
          send(parent, {:sse_token, token || ""})
          :ok
        end

        # Callback for workflow step progress
        on_workflow_progress = fn step_id, phase, meta ->
          Logger.debug(
            "[SSE Task] Workflow progress: #{inspect(step_id)} -> #{inspect(phase)}"
          )

          send(parent, {:sse_step_execution, step_id, phase, meta || %{}})
          :ok
        end

        Logger.info("[SSE Task] Callbacks created, executing stream function")

        try do
          result = stream_fn.(on_chunk, on_workflow_progress)
          Logger.info("[SSE Task] Stream function completed: #{inspect(elem(result, 0))}")
          send(parent, {:sse_result, result})
          Process.sleep(50)
          :ok
        rescue
          e ->
            Logger.error("[SSE Task] Stream function exception: #{Exception.message(e)}")
            Logger.error("[SSE Task] Stacktrace: #{inspect(__STACKTRACE__)}")

            error = %{
              "message" => "stream_execution_failed",
              "detail" => Exception.message(e)
            }

            send(parent, {:sse_result, {:error, %{reason: error}}})
            Process.sleep(50)
            :error
        end
      end)

    Logger.info("[SSE] Task created, sending open event")
    Process.sleep(10)

    case send_event(conn, StreamEvent.open()) do
      {:ok, conn} ->
        Logger.info("[SSE] Open event sent, entering event loop")
        event_loop(conn, task.ref)

      {:error, reason} ->
        Logger.error("[SSE] Failed to send open event: #{inspect(reason)}")
        Task.shutdown(task, :brutal_kill)
        conn
    end
  end

  # ========================================
  # Private Helper Functions
  # ========================================

  # Convert workflow engine phase to StreamEvent status
  defp phase_to_status(:start), do: "starting"
  defp phase_to_status(:complete), do: "completed"
  defp phase_to_status(:skip), do: "skipped"
  defp phase_to_status(:error), do: "failed"
  defp phase_to_status(other), do: to_string(other)

  # Build options keyword list for step_execution event
  defp build_step_opts(step_id, meta) do
    base_opts = [step_id: to_string(step_id)]

    cond do
      # Completed step with duration
      is_map(meta) and Map.has_key?(meta, :duration_ms) ->
        Keyword.put(base_opts, :execution_time_ms, meta.duration_ms)

      # Failed step with error
      is_map(meta) and Map.has_key?(meta, :error) ->
        Keyword.put(base_opts, :error, meta.error)

      # Default
      true ->
        base_opts
    end
  end

  # Convert step_id to human-readable name
  defp format_step_name(step_id) when is_atom(step_id) do
    step_id
    |> to_string()
    |> format_step_name()
  end

  defp format_step_name(step_id) when is_binary(step_id) do
    step_id
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp format_step_name(step_id), do: to_string(step_id)

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
