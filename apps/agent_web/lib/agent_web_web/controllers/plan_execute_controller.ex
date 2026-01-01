defmodule AgentWebWeb.PlanExecuteController do
  use AgentWebWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias AgentRuntime.Llm.PlanExecutor
  alias AgentCore.Llm.Profiles
  alias AgentWeb.Llm.InputMapper
  alias AgentWeb.Streaming.SseManager

  # NOTE:
  # - Controller is plan-driven: requires plan_id (and optional plan_version).
  # - No default steps here. No step wiring here.
  # - Runtime handles plan loading/resolution via configured PlanStore.

  def stream(conn, %{"profile_id" => profile_id, "plan_id" => plan_id, "input" => input} = params) do
    overrides = Map.get(params, "overrides", %{})
    plan_version = normalize_plan_version(Map.get(params, "plan_version"))

    if blank?(profile_id) or blank?(plan_id) or not is_map(input) do
      conn
      |> put_status(:bad_request)
      |> json(%{
        "status" => "error",
        "error" => "invalid_request",
        "details" => "Expected profile_id, plan_id and input"
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
            on_chunk,
            plan_id: plan_id,
            plan_version: plan_version,
            memory_store: AgentWeb.Memory.Store
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

  # -----------------------
  # Helpers
  # -----------------------

  defp build_exec_meta(params) do
    %{
      "trace_id" => blank_to_nil(Map.get(params, "trace_id")),
      "parent_run_id" => blank_to_nil(Map.get(params, "parent_run_id")),
      "conversation_id" => valid_uuid_or_nil(Map.get(params, "conversation_id"))
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp normalize_plan_version(nil), do: :latest

  defp normalize_plan_version(v) when is_integer(v) and v >= 0, do: v

  defp normalize_plan_version(v) when is_binary(v) do
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

  defp normalize_plan_version(_), do: :latest

  defp blank?(v) when is_binary(v), do: String.trim(v) == ""
  defp blank?(_), do: true

  defp blank_to_nil(v) when is_binary(v) do
    if String.trim(v) == "", do: nil, else: v
  end

  defp blank_to_nil(v), do: v

  defp valid_uuid_or_nil(v) when is_binary(v) do
    v = String.trim(v)

    case Ecto.UUID.cast(v) do
      {:ok, _} -> v
      :error -> nil
    end
  end

  defp valid_uuid_or_nil(_), do: nil

  defp normalize_error(%{"message" => _} = m), do: m
  defp normalize_error(%{message: _} = m), do: Map.new(m)
  defp normalize_error(reason) when is_binary(reason), do: %{"message" => reason}
  defp normalize_error(reason), do: %{"message" => inspect(reason)}
end
