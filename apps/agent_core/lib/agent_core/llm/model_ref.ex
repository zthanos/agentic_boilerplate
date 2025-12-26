defmodule AgentCore.Llm.ModelRef do
  @moduledoc """
  Identifies an LLM model as expected by the target provider (OpenAI-compatible server, etc.).
  """

  @enforce_keys [:name]
  defstruct [
    :name,
    :family,
    :context_window,
    :supports_json,
    :supports_tools
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          family: atom() | nil,
          context_window: pos_integer() | nil,
          supports_json: boolean() | nil,
          supports_tools: boolean() | nil
        }
end
