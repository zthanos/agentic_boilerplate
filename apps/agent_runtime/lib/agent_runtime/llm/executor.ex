defmodule AgentRuntime.Llm.Executor do
  @moduledoc """
  Single entry point for LLM execution.

  Responsible for:
  - resolving InvocationConfig
  - persisting run snapshot
  - run lifecycle (started / finished / failed)
  - provider routing & call
  """

  alias AgentCore.Llm.{Resolver, ProviderRequest}
  # alias AgentCore.Llm.RunSnapshots
  alias AgentCore.Llm.RunStore.Ecto, as: RunStore
  alias AgentRuntime.Llm.ProviderRouter
  alias AgentCore.Llm.{Resolver, ProviderRequest}
  alias AgentRuntime.Llm.ProviderRouter
  alias AgentCore.Llm.{Resolver, ProviderRequest, RunSnapshots}
  alias AgentRuntime.Llm.{ProviderRouter}



  def execute(profile, overrides, input) do
    started_at = System.monotonic_time(:millisecond)

    invocation = Resolver.resolve(profile, overrides)

    # 1) Build and persist run snapshot (idempotent via fingerprint)
    snapshot = RunSnapshots.from_config(invocation, invocation.overrides)
    _ = RunStore.put(snapshot)
    _ = RunStore.mark_started(snapshot.fingerprint)

    request =
      ProviderRequest.new(invocation, input, [], %{
        "profile_id" => to_string(invocation.profile_id),
        "provider" => to_string(invocation.provider),
        "model" => to_string(invocation.model),
        "policy_version" => invocation.policy_version,
        "fingerprint" => invocation.fingerprint
      })

    with {:ok, adapter} <- ProviderRouter.route(invocation.provider),
         {:ok, resp} <- adapter.call(request) do
      latency = System.monotonic_time(:millisecond) - started_at

      _ =
        RunStore.mark_finished(
          snapshot.fingerprint,
          %{
            usage: resp.usage,
            latency_ms: latency
          }
        )

      {:ok, resp}
    else
      {:error, reason} ->
        latency = System.monotonic_time(:millisecond) - started_at

        _ =
          RunStore.mark_failed(
            snapshot.fingerprint,
            reason,
            %{latency_ms: latency}
          )

        {:error, reason}
    end
  end


end
