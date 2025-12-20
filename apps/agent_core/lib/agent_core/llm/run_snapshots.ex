defmodule AgentCore.Llm.RunSnapshots do
  alias AgentCore.Llm.{InvocationConfig, RunSnapshot}

  @policy_version "merge_policy.v1"

  @spec from_config(InvocationConfig.t(), map() | nil) :: RunSnapshot.t()
  def from_config(%InvocationConfig{} = cfg, canonical_overrides \\ nil) do
    %RunSnapshot{
      fingerprint: cfg.fingerprint,
      profile_id: cfg.profile_id,
      profile_name: cfg.profile_name,
      provider: cfg.provider,
      model: cfg.model,
      policy_version: @policy_version,
      resolved_at: cfg.resolved_at,
      overrides: canonical_overrides,
      invocation_config: invocation_config_to_map(cfg)
    }
  end

  defp invocation_config_to_map(%InvocationConfig{} = cfg) do
    %{
      profile_id: cfg.profile_id,
      profile_name: cfg.profile_name,
      provider: cfg.provider,
      model: cfg.model,
      generation: cfg.generation,
      budgets: cfg.budgets,
      tools: cfg.tools,
      stop_list: cfg.stop_list,
      overrides: cfg.overrides,
      fingerprint: cfg.fingerprint,
      resolved_at: cfg.resolved_at
    }
  end
end
