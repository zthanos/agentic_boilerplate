defmodule AgentRuntime.Llm.ProfileSelectorTest do
  use ExUnit.Case, async: true

  alias AgentRuntime.Llm.ProfileSelector

  test "returns default mappings when no config provided" do
    assert ProfileSelector.for(:requirements) == "req_llm"
    assert ProfileSelector.for(:diagrams) == "diagram_llm"
    assert ProfileSelector.for(:chat) == "chat_llm"
    assert ProfileSelector.for(:code_analysis) == "code_llm"
  end

  test "falls back to default profile id for unknown use-case" do
    assert ProfileSelector.for(:unknown_use_case) == "chat_llm"
  end

  test "supports config overrides" do
    prev = Application.get_env(:agent_runtime, ProfileSelector, [])

    try do
      Application.put_env(:agent_runtime, ProfileSelector,
        default: "fallback_llm",
        mappings: %{requirements: "req_llm"}
      )

      assert ProfileSelector.for(:requirements) == "req_llm"
      assert ProfileSelector.for(:unknown) == "fallback_llm"
    after
      Application.put_env(:agent_runtime, ProfileSelector, prev)
    end
  end



end
