defmodule AgentCore.Llm.RunSnapshot do
  @enforce_keys [
    :run_id,
    :trace_id,
    :fingerprint,
    :profile_id,
    :provider,
    :model,
    :policy_version,
    :resolved_at,
    :invocation_config
  ]
  defstruct [
    :run_id,
    :trace_id,
    :parent_run_id,
    :phase,
    :fingerprint,
    :profile_id,
    :profile_name,
    :provider,
    :model,
    :policy_version,
    :resolved_at,
    :overrides,
    :invocation_config
  ]

  @type t :: %__MODULE__{
          run_id: String.t(),
          trace_id: String.t(),
          parent_run_id: String.t() | nil,
          phase: String.t() | nil,
          fingerprint: String.t(),
          profile_id: String.t() | integer(),
          profile_name: String.t() | nil,
          provider: atom() | String.t(),
          model: String.t() | atom(),
          policy_version: String.t(),
          resolved_at: DateTime.t(),
          overrides: map() | nil,
          invocation_config: map()
        }
end
