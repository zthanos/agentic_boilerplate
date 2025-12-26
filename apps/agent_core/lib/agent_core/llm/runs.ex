defmodule AgentCore.Llm.Runs do
  @moduledoc "Public API for managing LLM runs."

  alias AgentCore.Llm.RunSnapshot
  alias AgentCore.Llm.RunStore
  alias AgentCore.Llm.RunView

  defp store do
    Application.fetch_env!(:agent_core, __MODULE__)
    |> Keyword.fetch!(:store)
  end

  @type run_id :: RunStore.run_id()
  @type trace_id :: RunStore.trace_id()

  @spec put(RunSnapshot.t()) :: {:ok, run_id()} | {:error, term()}
  def put(%RunSnapshot{} = snap) do
    store().put(snap)
  end

  @spec get(String.t()) :: {:ok, RunView.t()} | {:error, :not_found} | {:error, term()}
  def get(run_id) when is_binary(run_id), do: store().get(run_id)

  @spec list(keyword()) :: {:ok, [RunView.t()]} | {:error, term()}
  def list(opts \\ []), do: store().list(opts)

  @doc """
  Convenience helper: latest run for a given fingerprint (configuration).
  Not a primary identifier.
  """
  @spec latest_by_fingerprint(String.t()) :: {:ok, RunSnapshot.t()} | {:error, :not_found} | {:error, term()}
  def latest_by_fingerprint(fp) when is_binary(fp) do
    case store().list(fingerprint: fp, limit: 1) do
      {:ok, [snap | _]} -> {:ok, snap}
      {:ok, []} -> {:error, :not_found}
      {:error, e} -> {:error, e}
    end
  end

  @doc """
  Convenience helper: list runs for a trace/workflow instance.
  """
  @spec list_by_trace(trace_id(), keyword()) :: {:ok, [RunSnapshot.t()]} | {:error, term()}
  def list_by_trace(trace_id, opts \\ []) when is_binary(trace_id) and is_list(opts) do
    store().list(Keyword.merge([trace_id: trace_id], opts))
  end

  @spec mark_started(run_id()) :: :ok | {:error, :not_found} | {:error, term()}
  def mark_started(run_id), do: normalize_lifecycle(store().mark_started(run_id))

  @spec mark_finished(run_id(), map()) :: :ok | {:error, :not_found} | {:error, term()}
  def mark_finished(run_id, outcome), do: normalize_lifecycle(store().mark_finished(run_id, outcome))

  @spec mark_failed(run_id(), term(), map()) :: :ok | {:error, :not_found} | {:error, term()}
  def mark_failed(run_id, reason, outcome), do: normalize_lifecycle(store().mark_failed(run_id, reason, outcome))

  defp normalize_lifecycle({:ok, _run_id}), do: :ok
  defp normalize_lifecycle({:error, :not_found}), do: {:error, :not_found}
  defp normalize_lifecycle({:error, e}), do: {:error, e}
end
