defmodule AgentRuntime.Llm.Executor do
  @moduledoc false

  alias AgentCore.Llm.{ProviderRequest, Resolver, RunSnapshots, Runs}
  alias AgentRuntime.Llm.{ModelResolver, ProviderRegistry}

  # New arity (controller uses this)
  def execute(profile, overrides, input, exec_meta) when is_map(exec_meta) do
    do_execute(profile, overrides, input, exec_meta)
  end

  # Keep old arity for existing callers
  def execute(profile, overrides, input) do
    do_execute(profile, overrides, input, %{})
  end

  defp do_execute(profile, overrides, input, exec_meta) do
    started_at = System.monotonic_time(:millisecond)

    invocation = Resolver.resolve(profile, overrides)

    meta = %{
      trace_id: Map.get(exec_meta, "trace_id") || Map.get(exec_meta, :trace_id),
      parent_run_id: Map.get(exec_meta, "parent_run_id") || Map.get(exec_meta, :parent_run_id),
      phase: Map.get(exec_meta, "phase") || Map.get(exec_meta, :phase)
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()

    snapshot = RunSnapshots.from_config(invocation, invocation.overrides, meta)

    # Persist + use run_id for lifecycle
    run_id =
      case Runs.put(snapshot) do
        {:ok, rid} -> rid
        {:error, e} -> return_persist_error(e, snapshot)
      end

    _ = Runs.mark_started(run_id)

    resolved_model = ModelResolver.resolve(invocation.provider, invocation.model)

    request =
      ProviderRequest.new(invocation, input, [], %{
        "profile_id" => to_string(invocation.profile_id),
        "provider" => to_string(invocation.provider),
        "model" => to_string(invocation.model),
        "resolved_model" => resolved_model,
        "policy_version" => invocation.policy_version,
        "fingerprint" => invocation.fingerprint,
        "run_id" => run_id,
        "trace_id" => snapshot.trace_id
      })

    :telemetry.execute(
      [:agent_runtime, :llm, :execute, :start],
      %{system_time: System.system_time()},
      %{provider: invocation.provider, model: invocation.model, resolved_model: resolved_model, run_id: run_id, trace_id: snapshot.trace_id}
    )

    with {:ok, adapter} <- ProviderRegistry.adapter(invocation.provider),
         {:ok, resp} <- adapter.call(request) do
      latency = System.monotonic_time(:millisecond) - started_at

      _ =
        Runs.mark_finished(run_id, %{
          usage: resp.usage,
          latency_ms: latency
        })

      :telemetry.execute(
        [:agent_runtime, :llm, :execute, :stop],
        %{duration_ms: latency},
        %{
          provider: invocation.provider,
          model: invocation.model,
          resolved_model: resolved_model,
          usage: resp.usage,
          status: :ok,
          run_id: run_id,
          trace_id: snapshot.trace_id
        }
      )

      {:ok,
       %{
         response: resp,
         run_id: run_id,
         trace_id: snapshot.trace_id,
         fingerprint: snapshot.fingerprint,
         latency_ms: latency
       }}
    else
      {:error, reason} ->
        latency = System.monotonic_time(:millisecond) - started_at

        _ = Runs.mark_failed(run_id, reason, %{latency_ms: latency})

        :telemetry.execute(
          [:agent_runtime, :llm, :execute, :error],
          %{duration_ms: latency},
          %{
            provider: invocation.provider,
            model: invocation.model,
            resolved_model: resolved_model,
            reason: reason,
            status: :error,
            run_id: run_id,
            trace_id: snapshot.trace_id
          }
        )

        {:error,
         %{
           reason: reason,
           run_id: run_id,
           trace_id: snapshot.trace_id,
           fingerprint: snapshot.fingerprint,
           latency_ms: latency
         }}
    end
  end

  defp return_persist_error(e, snapshot) do
    throw({:run_persist_failed, %{error: e, run_id: snapshot.run_id, trace_id: snapshot.trace_id}})
  end
end
