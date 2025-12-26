defmodule AgentRuntime.Llm.ProfileSelector do
  @moduledoc """
  Maps runtime use-cases to LLM profile ids.

  This is orchestration logic, therefore it belongs to agent_runtime.
  """

  @type use_case ::
          :requirements
          | :diagrams
          | :chat
          | :code_analysis

  @spec for(use_case()) :: String.t()
  def for(use_case) when is_atom(use_case) do
    mappings()
    |> Map.get(use_case, default_profile_id())
  end

  @spec mappings() :: %{optional(use_case()) => String.t()}
  def mappings do
    cfg =
      Application.get_env(:agent_runtime, __MODULE__, [])
      |> Keyword.get(:mappings, %{})
      |> normalize_keys()

    default_mappings()
    |> Map.merge(cfg)
  end

  defp default_mappings do
    %{
      requirements: "req_llm",
      diagrams: "diagram_llm",
      chat: "chat_llm",
      code_analysis: "code_llm"
    }
  end

  defp default_profile_id do
    Application.get_env(:agent_runtime, __MODULE__, [])
    |> Keyword.get(:default, "chat_llm")
    |> to_string()
  end

  defp normalize_keys(map) when is_map(map) do
    map
    |> Enum.map(fn
      {k, v} when is_binary(k) -> {String.to_atom(k), to_string(v)}
      {k, v} when is_atom(k) -> {k, to_string(v)}
      {k, v} -> {k, to_string(v)}
    end)
    |> Map.new()
  end
end
