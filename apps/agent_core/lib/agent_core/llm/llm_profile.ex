defmodule AgentCore.Llm.LLMProfile do
  @moduledoc """
  Persisted, user-selectable configuration for invoking an LLM.
  """

  alias AgentCore.Llm.{Provider, ModelRef, GenerationParams, Budgets}

  # Για profile που αποθηκεύεται σε DB, συνήθως ΔΕΝ enforce-άρεις :id
  @enforce_keys [:name, :provider, :model]
  defstruct [
    :id,
    :name,
    enabled: true,
    provider: nil,
    model: nil,
    generation: %GenerationParams{},
    budgets: %Budgets{},
    tools: [],
    stop_list: nil,
    tags: [],
    inserted_at: nil,
    updated_at: nil
  ]

  @type id :: String.t() | integer()

  @type t :: %__MODULE__{
          id: id() | nil,
          name: String.t(),
          enabled: boolean(),
          provider: Provider.t(),
          model: ModelRef.t(),
          generation: GenerationParams.t(),
          budgets: Budgets.t(),
          tools: [String.t() | atom()],
          stop_list: [String.t()] | nil,
          tags: [String.t()],
          inserted_at: DateTime.t() | NaiveDateTime.t() | nil,
          updated_at: DateTime.t() | NaiveDateTime.t() | nil
        }
end
