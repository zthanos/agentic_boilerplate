defmodule AgentCore.Llm.Executor do
  @moduledoc """
  Single entry point for LLM execution.

  Responsible for:
  - resolving InvocationConfig
  - persisting run snapshot
  - run lifecycle (started / finished / failed)
  - provider routing & call
  """

  alias AgentCore.Llm.{Resolver, ProviderContract, ProviderRouter}
  alias AgentCore.Llm.RunSnapshots
  alias AgentCore.Llm.RunStore.Ecto, as: RunStore

  @spec execute(term(), map(), map()) :: {:ok, term()} | {:error, term()}
  def execute(profile, overrides, input)
      when is_map(overrides) and is_map(input) do
    cfg = Resolver.resolve(profile, overrides)

    snap = RunSnapshots.from_config(cfg, cfg.overrides)
    _ = RunStore.put(snap)

    _ = RunStore.mark_started(cfg.fingerprint)

    request = ProviderContract.build_request(cfg, input)
    adapter = ProviderRouter.pick(cfg.provider)

    started_ms = System.monotonic_time(:millisecond)

    case adapter.call(request) do
      {:ok, resp} ->
        latency_ms = System.monotonic_time(:millisecond) - started_ms

        _ =
          RunStore.mark_finished(cfg.fingerprint, %{
            usage: resp.usage,
            latency_ms: latency_ms
          })

        {:ok, resp}

      {:error, reason} ->
        latency_ms = System.monotonic_time(:millisecond) - started_ms

        _ =
          RunStore.mark_failed(cfg.fingerprint, reason, %{
            latency_ms: latency_ms
          })

        {:error, reason}
    end
  end
end
