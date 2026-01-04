defmodule AgentWebWeb.AgentExecuteController do
  use AgentWebWeb, :controller

  alias AgentRuntime.Llm.AgentExecutor
  alias AgentCore.Llm.Profiles
  alias AgentWeb.Llm.InputMapper
  alias AgentWeb.Streaming.SseManager

  require Logger

  def stream(
        conn,
        %{"profile_id" => profile_id, "agent_id" => agent_id, "input" => input} = params
      ) do
    Logger.info("[Controller] ===== STREAM REQUEST START =====")
    Logger.info("[Controller] agent_id=#{agent_id}, profile_id=#{profile_id}")

    try do
      overrides = Map.get(params, "overrides", %{})
      agent_version = normalize_version(Map.get(params, "agent_version"))
      Logger.info("[Controller] agent_version=#{inspect(agent_version)}")

      exec_meta = build_exec_meta(params)
      Logger.info("[Controller] exec_meta=#{inspect(exec_meta)}")

      profile = Profiles.get!(profile_id)
      Logger.info("[Controller] Profile loaded successfully")

      with {:ok, runtime_input} <- InputMapper.to_runtime(input) do
        Logger.info("[Controller] Input mapped successfully")
        Logger.info("[Controller] runtime_input keys: #{inspect(Map.keys(runtime_input))}")

        # Setup SSE connection FIRST before doing anything else
        Logger.info("[Controller] Setting up SSE connection...")
        conn = SseManager.setup_sse_conn(conn)
        Logger.info("[Controller] SSE connection established successfully")

        Logger.info("[Controller] Starting stream_with_events...")

        result = SseManager.stream_with_events(conn, fn on_chunk, on_workflow_progress ->
          Logger.info("[Controller] Stream function invoked, callbacks ready")
          Logger.info("[Controller] Calling AgentExecutor.execute_agent_stream...")

          try do
            result = AgentExecutor.execute_agent_stream(
              profile,
              overrides,
              runtime_input,
              exec_meta,
              on_chunk,
              on_workflow_progress,
              agent_id: agent_id,
              agent_version: agent_version
            )
            Logger.info("[Controller] AgentExecutor completed: #{inspect(elem(result, 0))}")
            result
          rescue
            e ->
              Logger.error("[Controller] AgentExecutor EXCEPTION: #{inspect(e)}")
              Logger.error("[Controller] Exception message: #{Exception.message(e)}")
              Logger.error("[Controller] Stacktrace: #{inspect(__STACKTRACE__)}")
              {:error, %{reason: "agent_executor_exception", detail: Exception.message(e)}}
          catch
            :exit, reason ->
              Logger.error("[Controller] AgentExecutor EXIT: #{inspect(reason)}")
              {:error, %{reason: "agent_executor_exit", detail: inspect(reason)}}
            :throw, value ->
              Logger.error("[Controller] AgentExecutor THROW: #{inspect(value)}")
              {:error, %{reason: "agent_executor_throw", detail: inspect(value)}}
          end
        end)

        Logger.info("[Controller] stream_with_events completed")
        result
      else
        {:error, reason} ->
          Logger.error("[Controller] Input mapping FAILED: #{inspect(reason)}")
          conn |> put_status(:bad_request) |> json(%{"error" => normalize_error(reason)})
      end
    rescue
      e in Ecto.NoResultsError ->
        Logger.error("[Controller] Profile NOT FOUND: #{profile_id}")
        conn |> put_status(:not_found) |> json(%{"error" => "profile_not_found"})

      e ->
        Logger.error("[Controller] TOP-LEVEL EXCEPTION: #{inspect(e)}")
        Logger.error("[Controller] Exception message: #{Exception.message(e)}")
        Logger.error("[Controller] Stacktrace: #{inspect(__STACKTRACE__)}")
        conn |> put_status(:internal_server_error) |> json(%{"error" => Exception.message(e)})
    end
  rescue
    e in Ecto.NoResultsError ->
      Logger.error("[Controller] Profile not found: #{profile_id}")
      conn |> put_status(:not_found) |> json(%{"error" => "profile_not_found"})

    e ->
      Logger.error("[Controller] Unexpected error: #{inspect(e)}")
      Logger.error("[Controller] Stacktrace: #{inspect(__STACKTRACE__)}")
      conn |> put_status(:internal_server_error) |> json(%{"error" => Exception.message(e)})
  end

  defp build_exec_meta(params) do
    %{
      "trace_id" => blank_to_nil(Map.get(params, "trace_id")),
      "parent_run_id" => blank_to_nil(Map.get(params, "parent_run_id")),
      "conversation_id" => blank_to_nil(Map.get(params, "conversation_id"))
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp normalize_version(nil), do: :latest
  defp normalize_version(v) when is_integer(v) and v >= 0, do: v

  defp normalize_version(v) when is_binary(v) do
    v = String.trim(v)

    cond do
      v == "" ->
        :latest

      v == "latest" ->
        :latest

      true ->
        case Integer.parse(v) do
          {n, ""} when n >= 0 -> n
          _ -> :latest
        end
    end
  end

  defp normalize_version(_), do: :latest

  defp blank_to_nil(v) when is_binary(v), do: if(String.trim(v) == "", do: nil, else: v)
  defp blank_to_nil(v), do: v

  defp normalize_error(reason) when is_binary(reason), do: %{"message" => reason}
  defp normalize_error(reason), do: %{"message" => inspect(reason)}
end
