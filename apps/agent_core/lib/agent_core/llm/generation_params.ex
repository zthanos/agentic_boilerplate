defmodule AgentCore.Llm.GenerationParams do


  defstruct [
    temperature: 0.2,
    top_p: 1.0,
    max_output_tokens: nil,
    seed: nil,
    presence_penalty: nil,
    frequency_penalty: nil,
    stop: nil,
  ]

  @type t :: %__MODULE__{
    temperature: float(),
    top_p: float(),
    max_output_tokens: integer() | nil,
    seed: integer() | nil,
    presence_penalty: float() | nil,
    frequency_penalty: float() | nil,
    stop: [String.t()] | nil
  }

end
