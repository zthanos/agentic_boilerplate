defmodule AgentWebWeb.AgentExecuteController do
  use AgentWebWeb, :controller

  alias AgentRuntime.Llm.AgentExecutor
  alias AgentCore.Llm.Profiles
  alias AgentWeb.Llm.InputMapper
  alias AgentWeb.Streaming.SseManager

  def stream(
        conn,
        %{"profile_id" => profile_id, "agent_id" => agent_id, "input" => input} = params
      ) do
    overrides = Map.get(params, "overrides", %{})
    agent_version = normalize_version(Map.get(params, "agent_version"))

    exec_meta = build_exec_meta(params)
    profile = Profiles.get!(profile_id)

    with {:ok, runtime_input} <- InputMapper.to_runtime(input) do
      conn = SseManager.setup_sse_conn(conn)

      SseManager.stream_with_events(conn, fn on_chunk ->
        AgentExecutor.execute_agent_stream(
          profile,
          overrides,
          runtime_input,
          exec_meta,
          on_chunk,
          agent_id: agent_id,
          agent_version: agent_version
        )
      end)
    else
      {:error, reason} ->
        conn |> put_status(:bad_request) |> json(%{"error" => normalize_error(reason)})
    end
  rescue
    _e in Ecto.NoResultsError ->
      conn |> put_status(:not_found) |> json(%{"error" => "profile_not_found"})

    e ->
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
