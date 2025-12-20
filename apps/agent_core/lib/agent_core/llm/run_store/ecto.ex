defmodule AgentCore.Llm.RunStore.Ecto do
  @behaviour AgentCore.Llm.RunStore

  import Ecto.Query, only: [from: 2]

  alias AgentCore.Repo
  alias AgentCore.Llm.{RunSnapshot, RunRecord}

  @impl true
  def put(%RunSnapshot{} = snap) do
    overrides = deep_stringify_keys(snap.overrides || %{})
    invocation_config = deep_stringify_keys(snap.invocation_config || %{})

    attrs = %{
      fingerprint: snap.fingerprint,
      profile_id: to_string(snap.profile_id),
      profile_name: snap.profile_name,
      provider: to_string(snap.provider),
      model: to_string(snap.model),
      policy_version: snap.policy_version,
      resolved_at: snap.resolved_at,
      overrides: overrides || %{},
      invocation_config: invocation_config || %{}
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

  defp deep_stringify_keys(term) do
    cond do
      is_map(term) ->
        term
        |> Enum.map(fn {k, v} -> {to_string(k), deep_stringify_keys(v)} end)
        |> Map.new()

      is_list(term) ->
        Enum.map(term, &deep_stringify_keys/1)

      true ->
        term
    end
  end

end
