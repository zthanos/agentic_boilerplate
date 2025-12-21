defmodule AgentCore.Llm.ProviderRequest do
  @moduledoc """
  Provider-agnostic request contract.

  This is the boundary between:
  - Resolver / InvocationConfig
  - Provider adapter (OpenAI/Azure/req_llm/Ollama/etc.)
  """

  alias AgentCore.Llm.InvocationConfig
  alias AgentCore.Llm.Tools.ToolSpec

  @enforce_keys [:invocation, :input]
  defstruct [
    :invocation, # InvocationConfig.t()
    :input,      # %{type: :chat | :completion, messages: [...], prompt: ...}
    tools: [],   # [ToolSpec.t()] - canonical
    metadata: %{} # trace ids, run fingerprint, etc.
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

  @spec new(InvocationConfig.t(), input(), [ToolSpec.t()], map()) :: t()
  def new(invocation, input, tools \\ [], metadata \\ %{}) do
    %__MODULE__{invocation: invocation, input: input, tools: tools, metadata: metadata}
  end
end
