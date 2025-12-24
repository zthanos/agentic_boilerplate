defmodule AgentCore.Llm.Profiles do
  @moduledoc "Public API for managing LLM profiles."

  alias AgentCore.Llm.LLMProfile


  defp store do
    Application.fetch_env!(:agent_core, __MODULE__)
    |> Keyword.fetch!(:store)
  end

  @type id :: String.t() | atom()

  @spec put(LLMProfile.t()) :: {:ok, String.t()} | {:error, term()}
  def put(%LLMProfile{} = profile), do: store().put(profile)

  @spec get(id()) :: {:ok, LLMProfile.t()} | :error
  def get(id), do: store().get(id)

  @dialyzer {:nowarn_function, get!: 1}
  @spec get!(id()) :: AgentCore.Llm.LLMProfile.t() | no_return()
  def get!(id) do
    case store().get(id) do  # <-- Αλλαγή: ΚΑΛΕΣΕ ΤΟ ΠΑΝΩ get/1
      {:ok, %AgentCore.Llm.LLMProfile{} = profile} -> profile
      :error ->
        raise ArgumentError, "LLMProfile not found: #{inspect(id)}"
    end
  end

  @spec list(keyword()) :: [LLMProfile.t()]
  def list(opts \\ []), do: store().list(opts)
end
