defmodule AgentCore.Llm.Budgets do
  defstruct [
    :max_input_tokens,
    :max_output_tokens,
    :max_total_tokens,
    :max_cost_eur,
    :max_steps
  ]

  @type t :: %__MODULE__{
    max_input_tokens: integer() | nil,
    max_output_tokens: integer() | nil,
    max_total_tokens: integer() | nil,
    max_cost_eur: float() | nil,
    max_steps: integer() | nil,
  }

end
