defmodule AgentCore.Llm.RunStore.Memory do
  @behaviour AgentCore.Llm.RunStore
  alias AgentCore.Llm.RunSnapshot

  @table __MODULE__

  def start_link do
    :ets.new(@table, [:named_table, :public, read_concurrency: true])
    {:ok, self()}
  end

  @impl true
  def put(%RunSnapshot{} = snap) do
    record = %{
      snapshot: snap,
      status: "created",
      started_at: nil,
      finished_at: nil,
      error: nil,
      usage: nil,
      latency_ms: nil
    }

    :ets.insert(@table, {snap.fingerprint, record})
    {:ok, snap.fingerprint}
  end

  @impl true
  def get_by_fingerprint(fp) do
    case :ets.lookup(@table, fp) do
      [{^fp, %{snapshot: snap}}] -> {:ok, snap}
      [] -> {:error, :not_found}
    end
  end

  @impl true
  def list(_opts) do
    snaps =
      :ets.tab2list(@table)
      |> Enum.map(fn {_k, %{snapshot: snap}} -> snap end)

    {:ok, snaps}
  end

  @impl true
  def mark_started(fp) do
    update(fp, fn rec ->
      %{rec | status: "started", started_at: DateTime.utc_now()}
    end)
  end

  @impl true
  def mark_finished(fp, outcome \\ %{}) do
    update(fp, fn rec ->
      %{rec | status: "finished", finished_at: DateTime.utc_now()}
      |> apply_outcome(outcome)
    end)
  end

  @impl true
  def mark_failed(fp, error, outcome \\ %{}) do
    update(fp, fn rec ->
      %{rec | status: "failed", finished_at: DateTime.utc_now(), error: normalize_error(error)}
      |> apply_outcome(outcome)
    end)
  end

  defp update(fp, fun) do
    case :ets.lookup(@table, fp) do
      [{^fp, rec}] ->
        :ets.insert(@table, {fp, fun.(rec)})
        {:ok, fp}

      [] ->
        {:error, :not_found}
    end
  end

  defp apply_outcome(rec, outcome) when is_map(outcome) do
    rec
    |> maybe_put(:usage, Map.get(outcome, :usage))
    |> maybe_put(:latency_ms, Map.get(outcome, :latency_ms))
  end

  defp maybe_put(rec, _k, nil), do: rec
  defp maybe_put(rec, k, v), do: Map.put(rec, k, v)

  defp normalize_error(error) when is_binary(error), do: %{message: error}
  defp normalize_error(error) when is_map(error), do: error
  defp normalize_error(error), do: %{error: inspect(error)}
end
