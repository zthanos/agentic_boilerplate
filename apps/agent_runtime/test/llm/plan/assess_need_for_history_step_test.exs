defmodule AgentRuntime.Llm.Plan.Steps.AssessNeedForHistoryStepTest do
  use ExUnit.Case, async: true

  @moduletag :rag_history

  alias AgentRuntime.Llm.Plan.PlanContext
  alias AgentRuntime.Llm.Plan.Steps.AssessNeedForHistoryStep

  defmodule ExecutorStub do
    def execute(_profile, _overrides, llm_input, _exec_meta) do
      assert llm_input.type == :chat
      assert [%{role: :system, content: sys}, %{role: :user, content: user}] = llm_input.messages
      assert is_binary(sys) and String.trim(sys) != ""
      assert is_binary(user) and String.trim(user) != ""

      {:ok, %{response: %{output_text: ~s({"query":"user name"})}, run_id: "run-1"}}
    end
  end

  test "skips when user prompt is missing/blank" do
    ctx =
      %PlanContext{
        profile: %{id: "req_llm", name: "req_llm"},
        overrides: %{},
        input: %{"type" => "chat", "messages" => [%{"role" => "user", "content" => "   "}]},
        exec_meta: %{"conversation_id" => "conv-1"},
        decisions: %{},
        augmented_messages: []
      }

    {:cont, ctx2} =
      AssessNeedForHistoryStep.run(ctx,
        system_prompt: "Return JSON with query",
        assessor_profile: %{id: "req_llm", name: "req_llm"},
        executor: ExecutorStub
      )

    assert Map.get(ctx2.decisions, :history_query) == nil
  end

  test "skips when assessor_profile is missing" do
    ctx =
      %PlanContext{
        profile: nil,
        overrides: %{},
        input: %{
          "type" => "chat",
          "messages" => [%{"role" => "user", "content" => "do you know my name?"}]
        },
        exec_meta: %{"conversation_id" => "conv-1"},
        decisions: %{},
        augmented_messages: []
      }

    {:cont, ctx2} =
      AssessNeedForHistoryStep.run(ctx,
        system_prompt: "Return JSON with query",
        assessor_profile: nil,
        executor: ExecutorStub
      )

    assert Map.get(ctx2.decisions, :history_query) == nil
  end

  test "sets history_query from LLM JSON output when assessment succeeds" do
    ctx =
      %PlanContext{
        profile: %{id: "req_llm", name: "req_llm"},
        overrides: %{},
        input: %{
          "type" => "chat",
          "messages" => [%{"role" => "user", "content" => "do you know my name?"}]
        },
        exec_meta: %{"conversation_id" => "conv-1"},
        decisions: %{},
        augmented_messages: []
      }

    {:cont, ctx2} =
      AssessNeedForHistoryStep.run(ctx,
        system_prompt: "Return JSON {\"query\":\"...\"}",
        assessor_profile: %{id: "req_llm", name: "req_llm"},
        executor: ExecutorStub
      )

    assert Map.get(ctx2.decisions, :history_query) == "user name"
  end
end
