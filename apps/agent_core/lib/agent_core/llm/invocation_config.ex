defmodule AgentCore.Llm.InvocationConfig do
  @enforce_keys [:profile_id, :provider, :model]
  defstruct [
    :profile_id,
    :profile_name,
    :provider,
    :model,
    :generation,
    :budgets,
    :tools,
    :stop_list,
    :resolved_at,
    :overrides,
    :fingerprint
  ]

  @type t :: %__MODULE__{
          profile_id: String.t() | integer(),
          profile_name: String.t() | nil,
          provider: atom(),
          model: String.t() | atom(),
          generation: map(),
          budgets: map(),
          tools: [String.t()],
          stop_list: [String.t()],
          resolved_at: DateTime.t(),
          overrides: map(),
          fingerprint: String.t()
        }
end
