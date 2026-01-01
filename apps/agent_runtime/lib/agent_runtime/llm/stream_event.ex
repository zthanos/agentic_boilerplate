# apps/agent_runtime/lib/agent_runtime/llm/stream_event.ex
defmodule AgentRuntime.Llm.StreamEvent do
  @moduledoc """
  Represents an SSE event sent during LLM streaming execution.
  This is a runtime domain concept, independent of web transport.
  """

  @type event_type :: :open | :token | :done | :clarify | :error | :ping

  @type t :: %__MODULE__{
          event: event_type(),
          data: map()
        }

  defstruct [:event, :data]

  @doc """
  Creates a new stream event.
  """
  def new(event, data) when is_atom(event) and is_map(data) do
    %__MODULE__{event: event, data: data}
  end

  # Convenience constructors
  def open(), do: new(:open, %{"status" => "ok"})

  def token(token), do: new(:token, %{"token" => token || ""})

  def done(run_id, trace_id, fingerprint, latency_ms, usage) do
    new(:done, %{
      "run_id" => run_id,
      "trace_id" => trace_id,
      "fingerprint" => fingerprint,
      "latency_ms" => latency_ms,
      "usage" => usage
    })
  end

  def clarify(trace_id, question) do
    new(:clarify, %{
      "trace_id" => trace_id,
      "question" => question
    })
  end

  def error(error, run_id \\ nil, trace_id \\ nil, fingerprint \\ nil, latency_ms \\ nil) do
    data = %{"error" => error}

    data =
      data
      |> maybe_put("run_id", run_id)
      |> maybe_put("trace_id", trace_id)
      |> maybe_put("fingerprint", fingerprint)
      |> maybe_put("latency_ms", latency_ms)

    new(:error, data)
  end

  def ping() do
    new(:ping, %{"ts" => System.system_time(:millisecond)})
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
