defmodule AgentRuntime.Llm.Executor do
  @moduledoc false

  alias AgentCore.Llm.{ProviderRequest, Resolver, RunSnapshots}
  alias AgentCore.Llm.RunStore.Ecto, as: RunStore
  alias AgentRuntime.Llm.{ModelResolver, ProviderRegistry}

  def execute(profile, overrides, input) do
    started_at = System.monotonic_time(:millisecond)

    invocation = Resolver.resolve(profile, overrides)

    snapshot = RunSnapshots.from_config(invocation, invocation.overrides)
    _ = RunStore.put(snapshot)
    _ = RunStore.mark_started(snapshot.fingerprint)

    resolved_model = ModelResolver.resolve(invocation.provider, invocation.model)

    request =
      ProviderRequest.new(invocation, input, [], %{
        "profile_id" => to_string(invocation.profile_id),
        "provider" => to_string(invocation.provider),
        "model" => to_string(invocation.model),
        "resolved_model" => resolved_model,
        "policy_version" => invocation.policy_version,
        "fingerprint" => invocation.fingerprint
      })

    :telemetry.execute(
      [:agent_runtime, :llm, :execute, :start],
      %{system_time: System.system_time()},
      %{provider: invocation.provider, model: invocation.model, resolved_model: resolved_model}
    )

    with {:ok, adapter} <- ProviderRegistry.adapter(invocation.provider),
         {:ok, resp} <- adapter.call(request) do
      latency = System.monotonic_time(:millisecond) - started_at

      _ =
        RunStore.mark_finished(snapshot.fingerprint, %{
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
          status: :ok
        }
      )

      {:ok, resp}
    else
      {:error, reason} ->
        latency = System.monotonic_time(:millisecond) - started_at

        _ = RunStore.mark_failed(snapshot.fingerprint, reason, %{latency_ms: latency})

        :telemetry.execute(
          [:agent_runtime, :llm, :execute, :error],
          %{duration_ms: latency},
          %{
            provider: invocation.provider,
            model: invocation.model,
            resolved_model: resolved_model,
            reason: reason,
            status: :error
          }
        )

        {:error, reason}
    end
  end
end
