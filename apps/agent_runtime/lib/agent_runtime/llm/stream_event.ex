# apps/agent_runtime/lib/agent_runtime/llm/stream_event.ex
defmodule AgentRuntime.Llm.StreamEvent do
  @moduledoc """
  Represents an SSE event sent during LLM streaming execution.
  This is a runtime domain concept, independent of web transport.
  """

  @type event_type ::
          :open | :token | :done | :clarify | :error | :ping | :step_execution | :close

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

  def close() do
    new(:close, %{})
  end

  @doc """
  Creates a step execution event for workflow progress tracking.

  ## Parameters
  - step_name: Human-readable name of the workflow step
  - status: Current status ("starting", "completed", "failed", "skipped")
  - opts: Optional keyword list with additional data
    - :execution_time_ms - Time taken for step completion (for "completed" status)
    - :error - Error details (for "failed" status)
    - :step_id - Unique step identifier

  ## Examples
      iex> StreamEvent.step_execution("Generate Query", "starting")
      %StreamEvent{event: :step_execution, data: %{"step_name" => "Generate Query", "status" => "starting", "timestamp" => ...}}

      iex> StreamEvent.step_execution("Generate Query", "completed", execution_time_ms: 1250)
      %StreamEvent{event: :step_execution, data: %{"step_name" => "Generate Query", "status" => "completed", "timestamp" => ..., "execution_time_ms" => 1250}}
  """
  def step_execution(step_name, status, opts \\ [])
      when is_binary(step_name) and is_binary(status) do
    data = %{
      "step_name" => step_name,
      "status" => status,
      "timestamp" => System.system_time(:millisecond)
    }

    data =
      data
      |> maybe_put("execution_time_ms", opts[:execution_time_ms])
      |> maybe_put("error", opts[:error])
      |> maybe_put("step_id", opts[:step_id])

    new(:step_execution, data)
  end

  # Convenience constructors for step execution events
  def step_starting(step_name, opts \\ []) do
    step_execution(step_name, "starting", opts)
  end

  def step_completed(step_name, execution_time_ms, opts \\ []) do
    opts = Keyword.put(opts, :execution_time_ms, execution_time_ms)
    step_execution(step_name, "completed", opts)
  end

  def step_failed(step_name, error, opts \\ []) do
    opts = Keyword.put(opts, :error, error)
    step_execution(step_name, "failed", opts)
  end

  def step_skipped(step_name, opts \\ []) do
    step_execution(step_name, "skipped", opts)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
