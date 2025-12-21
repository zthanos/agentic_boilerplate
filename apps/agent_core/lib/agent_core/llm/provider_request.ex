defmodule AgentCore.Llm.ProviderRequest do
  @moduledoc "Provider-agnostic request contract."

  alias AgentCore.Llm.InvocationConfig
  alias AgentCore.Llm.Tools.ToolSpec

  @enforce_keys [:invocation, :input]
  defstruct [
    :invocation,
    :input,
    tools: [],
    metadata: %{}
  ]

  @type input_type :: :chat | :completion

  @type chat_message :: %{
          required(:role) => :system | :user | :assistant | :tool,
          optional(:content) => String.t(),
          optional(:name) => String.t(),
          optional(:tool_call_id) => String.t(),
          optional(:metadata) => map()
        }

  @type input :: %{
          required(:type) => input_type(),
          optional(:messages) => [chat_message()],
          optional(:prompt) => String.t()
        }

  @type t :: %__MODULE__{
          invocation: InvocationConfig.t(),
          input: input(),
          tools: [ToolSpec.t()],
          metadata: map()
        }

  def new(invocation, input, tools \\ [], metadata \\ %{}) do
    %__MODULE__{invocation: invocation, input: input, tools: tools, metadata: metadata}
  end
end
