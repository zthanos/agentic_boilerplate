defmodule AgentRuntime.Llm.Plan.Steps.RetrieveMemoryStepTest do
  use ExUnit.Case, async: true
  import Mox
  @moduletag :rag_history

  alias AgentRuntime.Llm.Plan.PlanContext
  alias AgentRuntime.Llm.Plan.Steps.RetrieveMemoryStep
  alias AgentCore.Llm.LLMProfile

  import Mox

  setup :set_mox_from_context
  setup :verify_on_exit!

  test "injects retrieved memory into augmented_messages when above threshold" do
    conv_id = "conv-1"

    # Minimal-but-valid profile for resolver/embed path
    profile = %LLMProfile{
      id: "req_llm",
      name: "req_llm",
      provider: :openai_compatible,
      model: "openai/gpt-oss-20b"
    }

    ctx =
      %PlanContext{
        profile: profile,
        overrides: %{},
        input: %{
          "type" => "chat",
          "messages" => [%{"role" => "user", "content" => "do you know my name?"}]
        },
        exec_meta: %{"conversation_id" => conv_id},
        decisions: %{history_query: "user's name"},
        augmented_messages: []
      }

    AgentRuntime.ExecutorMock
    |> expect(:embed, fn input, embed_profile, overrides, exec_meta ->
      assert input == "user's name"
      assert embed_profile["id"] == "embeddings_nomic_v15"
      assert is_map(overrides)
      assert is_map(exec_meta)
      {:ok, [0.1, 0.2, 0.3]}
    end)

    AgentRuntime.MemoryStoreMock
    |> expect(:search, fn conversation_id, vector, top_k ->
      assert conversation_id == conv_id
      assert vector == [0.1, 0.2, 0.3]
      assert top_k == 6  # default @top_k value
      {:ok, [%{text: "User: I am Thanos", score: 0.62}]}
    end)

    opts = [
      memory_store: AgentRuntime.MemoryStoreMock,
      executor: AgentRuntime.ExecutorMock,
      similarity_threshold: 0.40
    ]

    {:cont, ctx2} = RetrieveMemoryStep.run(ctx, opts)

    assert ctx2.decisions.needs_history == true
    assert length(ctx2.decisions.retrieved_memory) == 1

    assert Enum.any?(ctx2.augmented_messages, fn m ->
             content = Map.get(m, "content") || Map.get(m, :content) || ""
             role = Map.get(m, "role") || Map.get(m, :role) || ""

             String.contains?(to_string(role), "system") and
               String.contains?(content, "I am Thanos")
           end)
  end
end
