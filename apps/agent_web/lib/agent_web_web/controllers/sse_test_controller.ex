defmodule AgentWebWeb.SseTestController do
  use AgentWebWeb, :controller

  alias AgentWeb.Streaming.SseManager
  alias AgentRuntime.Llm.StreamEvent

  require Logger

  @doc """
  Simple test endpoint to verify SSE is working correctly.
  Access at: GET /api/sse/test
  """
  def test(conn, _params) do
    Logger.info("[SSETest] Starting SSE test")

    # Setup SSE connection
    conn = SseManager.setup_sse_conn(conn)

    # Send open event
    {:ok, conn} = SseManager.send_event(conn, StreamEvent.open())
    Logger.info("[SSETest] Sent open event")

    # Send a few test events
    Enum.reduce(1..5, conn, fn i, conn ->
      Process.sleep(500)
      {:ok, conn} = SseManager.send_event(conn, StreamEvent.token("Test token #{i}\n"))
      Logger.info("[SSETest] Sent token #{i}")
      conn
    end)

    # Send done event
    {:ok, conn} =
      SseManager.send_event(
        conn,
        StreamEvent.done("test_run", "test_trace", "test_fp", 2500, %{})
      )

    Logger.info("[SSETest] Sent done event")

    # Send close event
    {:ok, conn} = SseManager.send_event(conn, StreamEvent.close())
    Logger.info("[SSETest] Sent close event")

    conn
  end
end
