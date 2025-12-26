defmodule AgentCore.Llm.RunView do
  @enforce_keys [:run_id, :trace_id, :fingerprint, :profile_id, :provider, :model, :policy_version, :resolved_at, :status]
  defstruct [
    # identity / chaining
    :run_id,
    :trace_id,
    :parent_run_id,
    :phase,

    # config snapshot
    :fingerprint,
    :profile_id,
    :profile_name,
    :provider,
    :model,
    :policy_version,
    :resolved_at,
    :overrides,
    :invocation_config,

    # lifecycle / observability
    :status,
    :started_at,
    :finished_at,
    :usage,
    :latency_ms,
    :error,

    # audit
    :inserted_at,
    :updated_at
  ]

  @type t :: %__MODULE__{
          run_id: String.t(),
          trace_id: String.t(),
          parent_run_id: String.t() | nil,
          phase: String.t() | nil,
          fingerprint: String.t(),
          profile_id: String.t(),
          profile_name: String.t() | nil,
          provider: String.t() | atom(),
          model: String.t() | atom(),
          policy_version: String.t(),
          resolved_at: DateTime.t(),
          overrides: map() | nil,
          invocation_config: map(),
          status: String.t(),
          started_at: DateTime.t() | nil,
          finished_at: DateTime.t() | nil,
          usage: map() | nil,
          latency_ms: integer() | nil,
          error: map() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }
end
