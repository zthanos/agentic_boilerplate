defmodule AgentCore.Llm.ProviderResponse do
  @moduledoc "Provider-agnostic response contract."

  @enforce_keys [:output_text]
  defstruct [
    :output_text,
    raw: nil,
    usage: %{},
    finish_reason: nil,
    tool_calls: []
  ]

  @type tool_call :: %{
          required(:id) => String.t(),
          required(:name) => String.t(),
          optional(:arguments) => map(),
          optional(:raw_arguments) => any()
        }

  @type t :: %__MODULE__{
          output_text: String.t(),
          raw: any(),
          usage: map(),
          finish_reason: String.t() | nil,
          tool_calls: [tool_call()]
        }

  def ok(text, opts \\ []) when is_binary(text) do
    %__MODULE__{
      output_text: text,
      raw: Keyword.get(opts, :raw),
      usage: Keyword.get(opts, :usage, %{}),
      finish_reason: Keyword.get(opts, :finish_reason),
      tool_calls: Keyword.get(opts, :tool_calls, [])
    }
  end
end
