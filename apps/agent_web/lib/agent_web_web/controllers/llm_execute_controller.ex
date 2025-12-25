defmodule AgentWebWeb.LlmExecuteController do
  use AgentWebWeb, :controller

  alias AgentRuntime.Llm.Executor
  alias AgentCore.Llm.Profiles
  alias AgentWeb.Llm.InputMapper

  @doc """
  POST /api/llm/execute

  Body:
  {
    "profile_id": "req_llm",
    "input": { ... },
    "overrides": { ... },              // optional: LLM config overrides
    "trace_id": "uuid",                // optional: continue an existing trace
    "parent_run_id": "uuid",           // optional: link to previous step
    "phase": "draft|critique|revise|final" // optional
  }
  """
  def execute(conn, %{"profile_id" => profile_id, "input" => input} = params) do
    overrides = Map.get(params, "overrides", %{})

    # execution metadata (NOT model overrides)
    exec_meta = %{
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
      |> json(%{"status" => "error", "error" => Exception.message(e)})
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

  # Helpers

  defp fetch_field(map, keys) when is_map(map) do
    Enum.find_value(keys, fn k -> Map.get(map, k) end)
  end

  defp fetch_field(_other, _keys), do: nil

  defp normalize_error({type, value}), do: %{type: inspect(type), value: inspect(value)}
  defp normalize_error(%{__struct__: _} = struct), do: inspect(struct)
  defp normalize_error(other), do: inspect(other)
end
