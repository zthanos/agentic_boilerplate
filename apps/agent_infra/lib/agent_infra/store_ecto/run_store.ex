defmodule AgentInfra.StoreEcto.RunStore do
  @moduledoc """
  Ecto implementation of the RunStore behavior.

  This module implements the AgentCore.Stores.RunStore behavior using Ecto
  and PostgreSQL for persistence. It handles conversion between domain structs
  and database schemas.
  """

  @behaviour AgentCore.Stores.RunStore
  # @behaviour AgentCore.Llm.RunStore

  alias AgentCore.{Runs, Stores.RunStore}
  alias AgentCore.Llm.{RunSnapshot}
  alias AgentInfra.{Repo, Schema.Run}
  import Ecto.Query

  @impl RunStore
  def create(%Runs{} = run) do
    attrs = domain_to_schema_attrs(run)

    %Run{}
    |> Run.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, schema} -> {:ok, schema.run_id}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @impl AgentCore.Llm.RunStore
  def put(%RunSnapshot{} = snapshot) do
    attrs = snapshot_to_schema_attrs(snapshot)

    %Run{}
    |> Run.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, schema} -> {:ok, schema.run_id}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @impl RunStore
  def get(run_id) when is_binary(run_id) do
    case Repo.get(Run, run_id) do
      nil -> {:error, :not_found}
      schema -> {:ok, schema_to_domain(schema)}
    end
  end

  @impl RunStore
  def update(run_id, updates) when is_binary(run_id) and is_map(updates) do
    case Repo.get(Run, run_id) do
      nil ->
        {:error, :not_found}

      schema ->
        # Convert domain updates to schema format
        schema_updates = convert_updates_to_schema(updates)

        schema
        |> Run.changeset(schema_updates)
        |> Repo.update()
        |> case do
          {:ok, updated_schema} -> {:ok, schema_to_domain(updated_schema)}
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  @impl RunStore
  def delete(run_id) when is_binary(run_id) do
    case Repo.get(Run, run_id) do
      nil ->
        {:error, :not_found}

      schema ->
        case Repo.delete(schema) do
          {:ok, _} -> :ok
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  @impl RunStore
  def list(opts \\ []) do
    query = build_list_query(opts)

    try do
      runs =
        query
        |> Repo.all()
        |> Enum.map(&schema_to_domain/1)

      {:ok, runs}
    rescue
      error -> {:error, error}
    end
  end

  @impl AgentCore.Llm.RunStore
  def mark_started(run_id) when is_binary(run_id) do
    updates = %{
      status: "started",
      started_at: DateTime.utc_now()
    }

    case __MODULE__.update(run_id, updates) do
      {:ok, _run} -> {:ok, run_id}
      error -> error
    end
  end

  @impl AgentCore.Llm.RunStore
  def mark_finished(run_id, outcome) when is_binary(run_id) and is_map(outcome) do
    updates = %{
      status: "finished",
      finished_at: DateTime.utc_now(),
      usage: outcome
    }

    case __MODULE__.update(run_id, updates) do
      {:ok, _run} -> {:ok, run_id}
      error -> error
    end
  end

  @impl AgentCore.Llm.RunStore
  def mark_failed(run_id, error_reason, outcome) when is_binary(run_id) and is_map(outcome) do
    updates = %{
      status: "failed",
      finished_at: DateTime.utc_now(),
      error: %{reason: error_reason},
      usage: outcome
    }

    case __MODULE__.update(run_id, updates) do
      {:ok, _run} -> {:ok, run_id}
      error -> error
    end
  end

  @impl RunStore
  def mark_completed(run_id, outcome) when is_binary(run_id) and is_map(outcome) do
    mark_finished(run_id, outcome)
  end

  @impl RunStore
  def count(opts \\ []) do
    query = build_list_query(opts)

    try do
      count =
        query
        |> select([r], count(r.run_id))
        |> Repo.one()

      {:ok, count}
    rescue
      error -> {:error, error}
    end
  end

  @impl RunStore
  def latest_by_fingerprint(fingerprint) when is_binary(fingerprint) do
    query =
      from(r in Run,
        where: r.fingerprint == ^fingerprint,
        order_by: [desc: r.inserted_at],
        limit: 1
      )

    case Repo.one(query) do
      nil -> {:error, :not_found}
      schema -> {:ok, schema_to_domain(schema)}
    end
  end

  @impl RunStore
  def list_by_trace(trace_id, opts \\ []) when is_binary(trace_id) do
    base_query = from(r in Run, where: r.trace_id == ^trace_id)

    query = apply_query_options(base_query, opts)

    try do
      runs =
        query
        |> Repo.all()
        |> Enum.map(&schema_to_domain/1)

      {:ok, runs}
    rescue
      error -> {:error, error}
    end
  end

  # Private helper functions

  defp snapshot_to_schema_attrs(%RunSnapshot{} = snapshot) do
    %{
      run_id: snapshot.run_id,
      trace_id: snapshot.trace_id,
      parent_run_id: snapshot.parent_run_id,
      phase: snapshot.phase,
      fingerprint: snapshot.fingerprint,
      profile_id: snapshot.profile_id,
      profile_name: snapshot.profile_name,
      provider: to_string(snapshot.provider),
      model: snapshot.model,
      policy_version: snapshot.policy_version,
      resolved_at: snapshot.resolved_at,
      overrides: snapshot.overrides || %{},
      invocation_config: snapshot.invocation_config || %{},
      # New snapshots start as created
      status: "created",
      started_at: nil,
      finished_at: nil,
      error: nil,
      usage: nil,
      latency_ms: nil
    }
  end

  defp domain_to_schema_attrs(%Runs{} = run) do
    %{
      run_id: run.id,
      trace_id: run.trace_id,
      parent_run_id: run.parent_run_id,
      phase: run.phase,
      fingerprint: run.fingerprint,
      profile_id: to_string(run.profile_id),
      profile_name: run.profile_name,
      provider: to_string(run.provider),
      model: to_string(run.model),
      policy_version: run.policy_version,
      resolved_at: run.resolved_at,
      overrides: run.overrides || %{},
      invocation_config: run.invocation_config || %{},
      status: domain_status_to_schema(run.status),
      started_at: run.started_at,
      finished_at: run.finished_at,
      error: run.error_reason && %{reason: run.error_reason},
      usage: run.outcome,
      # Could be calculated from timestamps
      latency_ms: nil
    }
  end

  defp schema_to_domain(%Run{} = schema) do
    %Runs{
      id: schema.run_id,
      trace_id: schema.trace_id,
      parent_run_id: schema.parent_run_id,
      phase: schema.phase,
      fingerprint: schema.fingerprint,
      profile_id: schema.profile_id,
      profile_name: schema.profile_name,
      provider: schema.provider && String.to_existing_atom(schema.provider),
      model: schema.model,
      policy_version: schema.policy_version,
      status: schema_status_to_domain(schema.status),
      resolved_at: schema.resolved_at,
      started_at: schema.started_at,
      finished_at: schema.finished_at,
      overrides: schema.overrides,
      invocation_config: schema.invocation_config,
      outcome: schema.usage,
      error_reason: schema.error && schema.error["reason"],
      created_at: schema.inserted_at,
      updated_at: schema.updated_at
    }
  end

  defp build_list_query(opts) do
    base_query = from(r in Run)

    apply_query_options(base_query, opts)
  end

  defp apply_query_options(query, opts) do
    Enum.reduce(opts, query, fn
      {:trace_id, trace_id}, q ->
        from(r in q, where: r.trace_id == ^trace_id)

      {:profile_id, profile_id}, q ->
        from(r in q, where: r.profile_id == ^to_string(profile_id))

      {:status, status}, q ->
        from(r in q, where: r.status == ^to_string(status))

      {:fingerprint, fingerprint}, q ->
        from(r in q, where: r.fingerprint == ^fingerprint)

      {:limit, limit}, q ->
        from(r in q, limit: ^limit)

      {:offset, offset}, q ->
        from(r in q, offset: ^offset)

      {:order_by, :created_at_desc}, q ->
        from(r in q, order_by: [desc: r.inserted_at])

      {:order_by, :created_at_asc}, q ->
        from(r in q, order_by: [asc: r.inserted_at])

      {:order_by, field}, q when is_atom(field) ->
        from(r in q, order_by: [desc: ^field])

      _other, q ->
        q
    end)
  end

  # Status mapping functions
  defp domain_status_to_schema(:pending), do: "created"
  defp domain_status_to_schema(:running), do: "started"
  defp domain_status_to_schema(:completed), do: "finished"
  defp domain_status_to_schema(:failed), do: "failed"
  defp domain_status_to_schema(status) when is_binary(status), do: status

  defp schema_status_to_domain("created"), do: :pending
  defp schema_status_to_domain("started"), do: :running
  defp schema_status_to_domain("finished"), do: :completed
  defp schema_status_to_domain("failed"), do: :failed
  defp schema_status_to_domain(status) when is_atom(status), do: status

  # Convert domain update values to schema format
  defp convert_updates_to_schema(updates) do
    Enum.reduce(updates, %{}, fn
      {:status, status}, acc when is_atom(status) ->
        Map.put(acc, :status, domain_status_to_schema(status))

      {:provider, provider}, acc when is_atom(provider) ->
        Map.put(acc, :provider, to_string(provider))

      {:model, model}, acc when is_atom(model) ->
        Map.put(acc, :model, to_string(model))

      {key, value}, acc ->
        Map.put(acc, key, value)
    end)
  end
end
