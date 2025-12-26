defmodule AgentWebWeb.LlmExecuteController do
  use AgentWebWeb, :controller
  use OpenApiSpex.ControllerSpecs
  alias AgentWeb.OpenApi.Schemas

  alias AgentRuntime.Llm.Executor
  alias AgentCore.Llm.Profiles
  alias AgentWeb.Llm.InputMapper

  @doc """
  POST /api/llm/execute

  Body:
  {
    "profile_id": "req_llm",
    "input": { . },
    "overrides": { . },                 // optional: LLM config overrides
    "trace_id": "uuid",                 // optional: continue an existing trace
    "parent_run_id": "uuid",            // optional: link to previous step
    "phase": "draft|critique|revise|final" // optional
  }
  """
  operation :execute,
    summary: "Execute an LLM call",
    request_body: {"Execute request", "application/json", Schemas.LlmExecuteRequest},
    responses: [
      ok: {"OK", "application/json", Schemas.LlmExecuteResponseOk},
      bad_request: {"Bad Request", "application/json", Schemas.LlmExecuteResponseError},
      not_found: {"Not Found", "application/json", Schemas.LlmExecuteResponseError},
      internal_server_error: {"Internal Server Error", "application/json", Schemas.LlmExecuteResponseError}
    ]



  def execute(conn, %{"profile_id" => profile_id, "input" => input} = params) do
    overrides = Map.get(params, "overrides", %{})

    # execution metadata (NOT model overrides)
    exec_meta =
      %{
        "trace_id" => Map.get(params, "trace_id"),
        "parent_run_id" => Map.get(params, "parent_run_id"),
        "phase" => Map.get(params, "phase")
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    profile = Profiles.get!(profile_id)

    case InputMapper.to_runtime(input) do
      {:ok, runtime_input} ->
        case Executor.execute(profile, overrides, runtime_input, exec_meta) do
          {:ok, %{response: resp, run_id: run_id, trace_id: trace_id, fingerprint: fp, latency_ms: latency}} ->
            json(conn, %{
              "status" => "ok",
              "run_id" => run_id,
              "trace_id" => trace_id,
              "fingerprint" => fp,
              "latency_ms" => latency,
              "output_text" => fetch_field(resp, [:output_text, "output_text"]),
              "output" => fetch_field(resp, [:raw, "raw"]),
              "usage" => fetch_field(resp, [:usage, "usage"])
            })

          {:error, %{reason: reason, run_id: run_id, trace_id: trace_id, fingerprint: fp, latency_ms: latency}} ->
            conn
            |> put_status(:bad_request)
            |> json(%{
              "status" => "error",
              "run_id" => run_id,
              "trace_id" => trace_id,
              "fingerprint" => fp,
              "latency_ms" => latency,
              "error" => normalize_error(reason)
            })
        end

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          "status" => "error",
          "error" => normalize_error(reason)
        })
    end
  rescue
    _e in Ecto.NoResultsError ->
      conn
      |> put_status(:not_found)
      |> json(%{"status" => "error", "error" => "profile_not_found"})

    e ->
      conn
      |> put_status(:internal_server_error)
      |> json(%{
        "status" => "error",
        "error" => %{"message" => Exception.message(e)}
      })
  end

  def execute(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      "status" => "error",
      "error" => "invalid_request",
      "details" => "Expected profile_id and input"
    })
  end

  @doc """
  POST /api/llm/execute/stream

  Body:
  %{
    "profile_id" => ".",
    "input" => %{"type" => "chat", "messages" => [ ... ]},
    "overrides" => %{},
    "trace_id" => ".",
    "parent_run_id" => ".",
    "phase" => "."
  }
  """
  def stream(conn, %{"profile_id" => profile_id, "input" => input} = params) do
    overrides = Map.get(params, "overrides", %{})

    if is_nil(profile_id) or profile_id == "" or not is_map(input) do
      conn
      |> put_status(:bad_request)
      |> json(%{
        "status" => "error",
        "error" => "invalid_request",
        "details" => "Expected profile_id and input"
      })
    else
      exec_meta =
        %{
          "trace_id" => Map.get(params, "trace_id"),
          "parent_run_id" => Map.get(params, "parent_run_id"),
          "phase" => Map.get(params, "phase")
        }
        |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
        |> Map.new()

      profile = Profiles.get!(profile_id)

      with {:ok, runtime_input} <- InputMapper.to_runtime(input) do
        conn =
          conn
          |> put_resp_header("content-type", "text/event-stream")
          |> put_resp_header("cache-control", "no-cache")
          |> put_resp_header("connection", "keep-alive")
          |> send_chunked(200)

        # Controller process MUST own the stream (Bandit requirement).
        parent = self()

        send_event = fn conn2, event, data ->
          payload = Jason.encode!(data)

          case Plug.Conn.chunk(conn2, "event: #{event}\ndata: #{payload}\n\n") do
            {:ok, conn3} -> {:ok, conn3}
            {:error, reason} -> {:error, reason}
          end
        end

        # Spawn worker that runs the streaming call and relays tokens to controller.
        task =
          Task.async(fn ->
            on_chunk = fn token ->
              send(parent, {:sse_token, token || ""})
              :ok
            end

            result = Executor.execute_stream(profile, overrides, runtime_input, exec_meta, on_chunk)
            send(parent, {:sse_result, result})
            :ok
          end)

        # Optional: notify client we opened the stream
        case send_event.(conn, "open", %{"status" => "ok"}) do
          {:ok, conn2} -> sse_loop(conn2, send_event, task.ref)
          {:error, _reason} ->
            Task.shutdown(task, :brutal_kill)
            conn
        end
      else
        {:error, reason} ->
          conn
          |> put_status(:bad_request)
          |> json(%{"status" => "error", "error" => normalize_error(reason)})
      end
    end
  rescue
    _e in Ecto.NoResultsError ->
      conn
      |> put_status(:not_found)
      |> json(%{"status" => "error", "error" => "profile_not_found"})

    e ->
      conn
      |> put_status(:internal_server_error)
      |> json(%{"status" => "error", "error" => %{"message" => Exception.message(e)}})
  end


  # ---- Streaming receive loop (controller owns conn & chunk) ----

  defp sse_loop(conn, send_event, task_ref) do
    receive do
      {:sse_token, token} ->
        case send_event.(conn, "token", %{"token" => token}) do
          {:ok, conn2} ->
            sse_loop(conn2, send_event, task_ref)

          {:error, _reason} ->
            # client closed; stop quietly
            conn
        end

      {:sse_result, {:ok, %{run_id: run_id, trace_id: trace_id, fingerprint: fp, latency_ms: latency, response: resp}}} ->
        _ =
          send_event.(conn, "done", %{
            "run_id" => run_id,
            "trace_id" => trace_id,
            "fingerprint" => fp,
            "latency_ms" => latency,
            "usage" => fetch_field(resp, [:usage, "usage"])
          })

        conn

      {:sse_result, {:error, %{reason: reason, run_id: run_id, trace_id: trace_id, fingerprint: fp, latency_ms: latency}}} ->
        _ =
          send_event.(conn, "error", %{
            "run_id" => run_id,
            "trace_id" => trace_id,
            "fingerprint" => fp,
            "latency_ms" => latency,
            "error" => normalize_error(reason)
          })

        conn

      {:DOWN, ^task_ref, :process, _pid, reason} ->
        # Worker crashed before sending {:sse_result, ...}
        _ =
          send_event.(conn, "error", %{
            "error" => %{
              "message" => "stream_worker_crashed",
              "detail" => inspect(reason)
            }
          })

        conn
    after
      60_000 ->
        # Keep-alive ping so intermediaries don't kill the connection
        case send_event.(conn, "ping", %{"ts" => System.system_time(:millisecond)}) do
          {:ok, conn2} -> sse_loop(conn2, send_event, task_ref)
          {:error, _reason} -> conn
        end
    end
  end

  # ---- Helpers (as in your existing controller) ----

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
