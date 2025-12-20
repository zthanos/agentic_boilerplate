defmodule AgentCore.Llm.InvocationConfig do
  @enforce_keys [:profile_id, :provider, :model]
  defstruct [
    :profile_id,
    :profile_name,
    :provider,
    :model,

    # fully resolved domains
    :generation,
    :budgets,
    :tools,
    :stop_list,

    # debug/audit metadata
    :resolved_at,
    :overrides,
    :fingerprint
  ]
end
