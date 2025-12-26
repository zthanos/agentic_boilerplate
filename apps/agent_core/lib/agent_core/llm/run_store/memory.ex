defmodule AgentCore.Llm.RunStore.Memory do
  @behaviour AgentCore.Llm.RunStore

  alias AgentCore.Llm.RunSnapshot

  @table __MODULE__

  def start_link do
    :ets.new(@table, [:named_table, :public, read_concurrency: true])
    {:ok, self()}
  end

  # -----------------------
  # RunStore callbacks
  # -----------------------

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

    :ets.insert(@table, {snap.run_id, record})
    {:ok, snap.run_id}
  end

  @impl true
  def get(run_id) when is_binary(run_id) do
    case :ets.lookup(@table, run_id) do
      [{^run_id, %{snapshot: snap}}] -> {:ok, snap}
      [] -> {:error, :not_found}
    end
  end

  @impl true
  def list(opts \\ []) when is_list(opts) do
    runs =
      :ets.tab2list(@table)
      |> Enum.map(fn {_run_id, rec} -> rec end)
      |> apply_filters(opts)
      |> apply_order(opts)
      |> apply_limit(opts)
      |> Enum.map(fn %{snapshot: snap} -> snap end)

    {:ok, runs}
  end

  @impl true
  def mark_started(run_id) when is_binary(run_id) do
    update(run_id, fn rec ->
      # idempotent-ish
      started_at = rec.started_at || DateTime.utc_now()
      %{rec | status: "started", started_at: started_at}
    end)
  end

  @impl true
  def mark_finished(run_id, outcome \\ %{}) when is_binary(run_id) and is_map(outcome) do
    update(run_id, fn rec ->
      rec
      |> Map.merge(%{status: "finished", finished_at: DateTime.utc_now(), error: nil})
      |> apply_outcome(outcome)
    end)
  end

  @impl true
  def mark_failed(run_id, error, outcome \\ %{}) when is_binary(run_id) and is_map(outcome) do
    update(run_id, fn rec ->
      rec
      |> Map.merge(%{status: "failed", finished_at: DateTime.utc_now(), error: normalize_error(error)})
      |> apply_outcome(outcome)
    end)
  end

  # -----------------------
  # Internal helpers
  # -----------------------

  defp update(run_id, fun) do
    case :ets.lookup(@table, run_id) do
      [{^run_id, rec}] ->
        :ets.insert(@table, {run_id, fun.(rec)})
        {:ok, run_id}

      [] ->
        {:error, :not_found}
    end
  end

  defp apply_outcome(rec, outcome) when is_map(outcome) do
    usage = Map.get(outcome, :usage) || Map.get(outcome, "usage")
    latency_ms = Map.get(outcome, :latency_ms) || Map.get(outcome, "latency_ms")

    rec
    |> maybe_put(:usage, usage)
    |> maybe_put(:latency_ms, latency_ms)
  end

  defp maybe_put(rec, _k, nil), do: rec
  defp maybe_put(rec, k, v), do: Map.put(rec, k, v)

  # ---------- list/1 helpers ----------

  defp apply_filters(recs, opts) do
    Enum.filter(recs, fn %{snapshot: snap, status: status} ->
      matches?(:run_id, snap.run_id, opts) and
        matches?(:trace_id, snap.trace_id, opts) and
        matches?(:fingerprint, snap.fingerprint, opts) and
        matches_profile_id?(snap.profile_id, opts) and
        matches?(:status, status, opts)
    end)
  end

  defp matches?(key, value, opts) do
    case Keyword.get(opts, key) do
      nil -> true
      expected -> value == expected
    end
  end

  defp matches_profile_id?(profile_id, opts) do
    case Keyword.get(opts, :profile_id) do
      nil -> true
      expected -> to_string(profile_id) == to_string(expected)
    end
  end

  defp apply_order(recs, opts) do
    case Keyword.get(opts, :order) do
      :asc ->
        Enum.sort_by(recs, fn rec -> rec.snapshot.resolved_at end, DateTime)

      _ ->
        # default newest-first
        Enum.sort_by(recs, fn rec -> rec.snapshot.resolved_at end, {:desc, DateTime})
    end
  end

  defp apply_limit(recs, opts) do
    case Keyword.get(opts, :limit) do
      limit when is_integer(limit) and limit > 0 -> Enum.take(recs, limit)
      _ -> recs
    end
  end

  # ---------- error normalization ----------

  defp normalize_error(%{type: _t, value: _v} = map), do: map
  defp normalize_error(error) when is_binary(error), do: %{type: "error", value: error}
  defp normalize_error(error) when is_map(error), do: error
  defp normalize_error({type, value}), do: %{type: inspect(type), value: inspect(value)}
  defp normalize_error(error), do: %{type: "error", value: inspect(error)}
end
