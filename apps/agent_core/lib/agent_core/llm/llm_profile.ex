defmodule AgentCore.Llm.LLMProfile do
  @moduledoc """
  Persisted, user-selectable configuration for invoking an LLM.
  """

  alias AgentCore.Llm.{Provider, ModelRef, GenerationParams, Budgets}

  # Για profile που αποθηκεύεται σε DB, συνήθως ΔΕΝ enforce-άρεις :id
  @enforce_keys [:name, :provider_id, :model]
  defstruct [
    :id,
    :name,
    enabled: true,
    provider_id: nil,  # References provider ID from database
    model: nil,
    policy_version: nil,
    generation: %GenerationParams{},
    budgets: %Budgets{},
    tools: [],
    stop_list: [],
    tags: [],
    inserted_at: nil,
    updated_at: nil
  ]

  @type id :: String.t() | integer()
  @type provider_id :: String.t() | integer()  # References database provider ID

  @type t :: %__MODULE__{
          id: id() | nil,
          name: String.t(),
          enabled: boolean(),
          provider_id: provider_id(),  # References database provider ID
          model: ModelRef.t(),
          policy_version: String.t() | nil,
          generation: GenerationParams.t(),
          budgets: Budgets.t(),
          tools: [String.t() | atom()],
          stop_list: [String.t()],
          tags: [String.t()],
          inserted_at: DateTime.t() | NaiveDateTime.t() | nil,
          updated_at: DateTime.t() | NaiveDateTime.t() | nil
        }
end
