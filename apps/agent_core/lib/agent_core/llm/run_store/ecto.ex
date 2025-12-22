defmodule AgentCore.Llm.RunStore.Ecto do
  @behaviour AgentCore.Llm.RunStore

  import Ecto.Query, only: [from: 2]

  alias AgentCore.Repo
  alias AgentCore.Llm.{RunSnapshot, RunRecord}
  alias AgentCore.RunStore.Serialization

  @impl true
    def put(%RunSnapshot{} = snap) do
    overrides =
      snap.overrides
      |> Kernel.||(%{})
      |> Serialization.deep_jsonify()
      # |> deep_sort()  # optional

    invocation_config =
      snap.invocation_config
      |> Kernel.||(%{})
      |> Serialization.deep_jsonify()
      # |> deep_sort()  # optional

    attrs = %{
      fingerprint: snap.fingerprint,
      profile_id: to_string(snap.profile_id),
      profile_name: snap.profile_name,
      provider: to_string(snap.provider),
      model: to_string(snap.model),
      policy_version: snap.policy_version,
      resolved_at: snap.resolved_at,
      overrides: overrides,
      invocation_config: invocation_config
    }

    %RunRecord{}
    |> RunRecord.changeset(attrs)
    |> Repo.insert(on_conflict: :nothing, conflict_target: :fingerprint)
    |> case do
      {:ok, _rec} ->
        {:ok, snap.fingerprint}

      {:error, cs} ->
        # If conflict, it will still return {:error, cs} depending on adapter;
        # robust fallback: fetch existing.
        case Repo.get(RunRecord, snap.fingerprint) do
          nil -> {:error, cs}
          _rec -> {:ok, snap.fingerprint}
        end
    end
  end


  @impl true
  def get_by_fingerprint(fp) when is_binary(fp) do
    case Repo.get(RunRecord, fp) do
      nil -> {:error, :not_found}
      rec -> {:ok, to_snapshot(rec)}
    end
  end

  @impl true
  def list(opts) do
    limit = Keyword.get(opts, :limit, 50)

    q =
      from r in RunRecord,
        order_by: [desc: r.resolved_at],
        limit: ^limit

    {:ok, Repo.all(q) |> Enum.map(&to_snapshot/1)}
  end

  defp to_snapshot(%RunRecord{} = rec) do
    %RunSnapshot{
      fingerprint: rec.fingerprint,
      profile_id: rec.profile_id,
      profile_name: rec.profile_name,
      provider: rec.provider,
      model: rec.model,
      policy_version: rec.policy_version,
      resolved_at: rec.resolved_at,
      overrides: rec.overrides,
      invocation_config: rec.invocation_config
    }
  end

  def mark_started(fingerprint) when is_binary(fingerprint) do
    now = DateTime.utc_now()

    RunRecord
    |> Repo.get(fingerprint)
    |> case do
      nil ->
        {:error, :not_found}

      rec ->
        # Do not overwrite started_at if already set (idempotent)
        attrs =
          rec
          |> Map.get(:started_at)
          |> case do
            nil -> %{status: "started", started_at: now}
            _ -> %{status: "started"}
          end

        rec
        |> RunRecord.changeset(attrs)
        |> Repo.update()
        |> case do
          {:ok, _} -> {:ok, fingerprint}
          {:error, cs} -> {:error, cs}
        end
    end
  end

  def mark_finished(fingerprint, outcome \\ %{}) when is_binary(fingerprint) and is_map(outcome) do
    now = DateTime.utc_now()

    RunRecord
    |> Repo.get(fingerprint)
    |> case do
      nil ->
        {:error, :not_found}

      rec ->
        latency_ms = compute_latency_ms(rec.started_at, now)

        attrs = %{
          status: "finished",
          finished_at: now,
          usage: Map.get(outcome, :usage) || Map.get(outcome, "usage"),
          latency_ms: Map.get(outcome, :latency_ms) || Map.get(outcome, "latency_ms") || latency_ms
        }

        rec
        |> RunRecord.changeset(attrs)
        |> Repo.update()
        |> case do
          {:ok, _} -> {:ok, fingerprint}
          {:error, cs} -> {:error, cs}
        end
    end
  end

  def mark_failed(fingerprint, error, outcome \\ %{})
      when is_binary(fingerprint) do
    now = DateTime.utc_now()

    RunRecord
    |> Repo.get(fingerprint)
    |> case do
      nil ->
        {:error, :not_found}

      rec ->
        latency_ms = compute_latency_ms(rec.started_at, now)

        attrs = %{
          status: "failed",
          finished_at: now,
          error: normalize_error(error),
          usage: Map.get(outcome, :usage) || Map.get(outcome, "usage"),
          latency_ms: Map.get(outcome, :latency_ms) || Map.get(outcome, "latency_ms") || latency_ms
        }

        rec
        |> RunRecord.changeset(attrs)
        |> Repo.update()
        |> case do
          {:ok, _} -> {:ok, fingerprint}
          {:error, cs} -> {:error, cs}
        end
    end
  end

  defp compute_latency_ms(nil, _now), do: nil
  defp compute_latency_ms(%DateTime{} = started_at, %DateTime{} = now) do
    diff_us = DateTime.diff(now, started_at, :microsecond)
    div(max(diff_us, 0), 1000)
  end

  defp normalize_error(%Ecto.Changeset{} = cs) do
    %{type: "changeset", errors: Ecto.Changeset.traverse_errors(cs, fn {msg, _} -> msg end)}
  end

  defp normalize_error(%{__exception__: true} = ex) do
    %{type: "exception", module: inspect(ex.__struct__), message: Exception.message(ex)}
  end

  defp normalize_error(other) do
    %{type: "error", value: inspect(other)}
  end



end
