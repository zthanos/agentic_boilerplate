# apps/agent_web/lib/agent_web_web/controllers/llm_execute_controller.ex
defmodule AgentWebWeb.PlanExecuteController do
  use AgentWebWeb, :controller
  use OpenApiSpex.ControllerSpecs
  alias AgentWeb.OpenApi.Schemas

  alias AgentRuntime.Llm.PlanExecutor
  alias AgentCore.Llm.Profiles
  alias AgentWeb.Llm.InputMapper
  alias AgentWeb.Streaming.SseManager

  # ... execute/2 remains unchanged ...

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
      exec_meta = build_exec_meta(params)
      profile = Profiles.get!(profile_id)

      with {:ok, runtime_input} <- InputMapper.to_runtime(input) do
        conn = SseManager.setup_sse_conn(conn)

        SseManager.stream_with_events(conn, fn on_chunk ->
          PlanExecutor.execute_plan_stream(
            profile,
            overrides,
            runtime_input,
            exec_meta,
            on_chunk
          )
        end)
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

  # Helper functions

  defp build_exec_meta(params) do
    %{
      "trace_id" => Map.get(params, "trace_id"),
      "parent_run_id" => Map.get(params, "parent_run_id"),
      "phase" => Map.get(params, "phase")
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
    |> Map.new()
  end

  defp normalize_error(%{"message" => _} = m), do: m
  defp normalize_error(%{message: _} = m), do: Map.new(m)
  defp normalize_error(reason) when is_binary(reason), do: %{"message" => reason}
  defp normalize_error(reason), do: %{"message" => inspect(reason)}
end
