defmodule AgentWeb.Llm.RunStoreEcto do
  @moduledoc false

  @behaviour AgentCore.Llm.RunStore

  import Ecto.Query, only: [from: 2]

  alias AgentCore.Llm.RunSnapshot
  alias AgentWeb.Repo
  alias AgentWeb.Schemas.RunRecord
  alias AgentWeb.Support.Serialization

  # -----------------------
  # Public API (RunStore)
  # -----------------------

  @impl true
  def put(%RunSnapshot{} = snap) do
    overrides =
      snap.overrides
      |> Kernel.||(%{})
      |> Serialization.deep_jsonify()

    invocation_config =
      snap.invocation_config
      |> Kernel.||(%{})
      |> Serialization.deep_jsonify()

    attrs = %{
      run_id: snap.run_id,
      trace_id: snap.trace_id,
      parent_run_id: snap.parent_run_id,
      phase: snap.phase,
      fingerprint: snap.fingerprint,
      profile_id: to_string(snap.profile_id),
      profile_name: snap.profile_name,
      provider: to_string(snap.provider),
      model: to_string(snap.model),
      policy_version: snap.policy_version,
      resolved_at: snap.resolved_at,
      overrides: overrides,
      invocation_config: invocation_config,
      status: "created"
    }

    %RunRecord{}
    |> RunRecord.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, _rec} -> {:ok, snap.run_id}
      {:error, cs} -> {:error, cs}
    end
  end

  @impl true
  def get(run_id) when is_binary(run_id) do
    case Repo.get(RunRecord, run_id) do
      nil -> {:error, :not_found}
      rec -> {:ok, to_snapshot(rec)}
    end
  end

  @impl true
  def list(opts \\ []) when is_list(opts) do
    query =
      from r in RunRecord,
        order_by: [desc: r.inserted_at]

    query =
      case Keyword.get(opts, :run_id) do
        nil -> query
        run_id -> from r in query, where: r.run_id == ^run_id
      end

    query =
      case Keyword.get(opts, :trace_id) do
        nil -> query
        trace_id -> from r in query, where: r.trace_id == ^trace_id
      end

    query =
      case Keyword.get(opts, :fingerprint) do
        nil -> query
        fp -> from r in query, where: r.fingerprint == ^fp
      end

    query =
      case Keyword.get(opts, :profile_id) do
        nil -> query
        pid -> from r in query, where: r.profile_id == ^to_string(pid)
      end

    query =
      case Keyword.get(opts, :status) do
        nil -> query
        status -> from r in query, where: r.status == ^to_string(status)
      end

    query =
      case Keyword.get(opts, :limit) do
        nil -> query
        limit when is_integer(limit) and limit > 0 -> from r in query, limit: ^limit
        _ -> query
      end

    runs =
      query
      |> Repo.all()
      |> Enum.map(&to_snapshot/1)

    {:ok, runs}
  end

  @impl true
  def mark_started(run_id) when is_binary(run_id) do
    now = DateTime.utc_now()

    case Repo.get(RunRecord, run_id) do
      nil ->
        {:error, :not_found}

      rec ->
        attrs =
          if is_nil(rec.started_at) do
            %{status: "started", started_at: now}
          else
            %{status: "started"}
          end

        rec
        |> RunRecord.changeset(attrs)
        |> Repo.update()
        |> case do
          {:ok, _} -> {:ok, run_id}
          {:error, cs} -> {:error, cs}
        end
    end
  end

  @impl true
  def mark_finished(run_id, outcome \\ %{}) when is_binary(run_id) and is_map(outcome) do
    now = DateTime.utc_now()

    case Repo.get(RunRecord, run_id) do
      nil ->
        {:error, :not_found}

      rec ->
        latency_ms =
          Map.get(outcome, :latency_ms) ||
            Map.get(outcome, "latency_ms") ||
            compute_latency_ms(rec.started_at, now)

        usage =
          Map.get(outcome, :usage) ||
            Map.get(outcome, "usage")

        attrs = %{
          status: "finished",
          finished_at: now,
          error: nil,
          usage: usage,
          latency_ms: latency_ms
        }

        rec
        |> RunRecord.changeset(attrs)
        |> Repo.update()
        |> case do
          {:ok, _} -> {:ok, run_id}
          {:error, cs} -> {:error, cs}
        end
    end
  end

  @impl true
  def mark_failed(run_id, error, outcome \\ %{}) when is_binary(run_id) and is_map(outcome) do
    now = DateTime.utc_now()

    case Repo.get(RunRecord, run_id) do
      nil ->
        {:error, :not_found}

      rec ->
        latency_ms =
          Map.get(outcome, :latency_ms) ||
            Map.get(outcome, "latency_ms") ||
            compute_latency_ms(rec.started_at, now)

        usage =
          Map.get(outcome, :usage) ||
            Map.get(outcome, "usage")

        attrs = %{
          status: "failed",
          finished_at: now,
          error: normalize_error(error),
          usage: usage,
          latency_ms: latency_ms
        }

        rec
        |> RunRecord.changeset(attrs)
        |> Repo.update()
        |> case do
          {:ok, _} -> {:ok, run_id}
          {:error, cs} -> {:error, cs}
        end
    end
  end

  # -----------------------
  # Convenience helpers
  # -----------------------

  # Optional helper for “latest run by fingerprint”
  def get_latest_by_fingerprint(fp) when is_binary(fp) do
    query =
      from r in RunRecord,
        where: r.fingerprint == ^fp,
        order_by: [desc: r.inserted_at],
        limit: 1

    case Repo.one(query) do
      nil -> {:error, :not_found}
      rec -> {:ok, to_snapshot(rec)}
    end
  end

  # -----------------------
  # Internal helpers
  # -----------------------

  defp to_snapshot(%RunRecord{} = r) do
    %RunSnapshot{
      run_id: r.run_id,
      trace_id: r.trace_id,
      parent_run_id: r.parent_run_id,
      phase: r.phase,
      fingerprint: r.fingerprint,
      profile_id: r.profile_id,
      profile_name: r.profile_name,
      provider: r.provider,
      model: r.model,
      policy_version: r.policy_version,
      resolved_at: r.resolved_at,
      overrides: r.overrides || %{},
      invocation_config: r.invocation_config || %{}
    }
  end

  defp compute_latency_ms(nil, _now), do: nil

  defp compute_latency_ms(%DateTime{} = started_at, %DateTime{} = now) do
    DateTime.diff(now, started_at, :millisecond)
  end

  defp normalize_error(%{type: _t, value: _v} = map), do: map
  defp normalize_error(%{__struct__: _} = struct), do: %{type: "error", value: inspect(struct)}
  defp normalize_error({type, value}), do: %{type: inspect(type), value: inspect(value)}
  defp normalize_error(other), do: %{type: "error", value: inspect(other)}
end
