defmodule AgentCore.WorkflowEngine.HistoryWorkflowIntegrationTest do
  use ExUnit.Case, async: true

  alias AgentCore.WorkflowEngine.{Context, HistoryWorkflow}

  alias AgentCore.WorkflowEngine.HistoryWorkflow.{
    AssessNeedStep,
    BuildQueryStep,
    RetrieveCandidatesStep,
    RerankCandidatesStep,
    ComposeContextStep,
    DoneStep
  }

  describe "step integration" do
    test "assess need step works correctly" do
      ctx = Context.new()
      input = %{current_message: "What did we discuss before?", conversation_id: "conv_123"}

      {:ok, updated_ctx, output} = AssessNeedStep.run(ctx, input, %{})

      assert Context.get_decision(updated_ctx, :needs_history) == true
      assert output.needs_history == true
      assert output.has_conversation_id == true
    end

    test "build query step works correctly" do
      ctx = Context.new()
      input = %{current_message: "Tell me about the project status", conversation_id: "conv_123"}

      {:ok, updated_ctx, output} = BuildQueryStep.run(ctx, input, %{})

      query = Context.get_artifact(updated_ctx, :history_query)
      assert is_map(query)
      assert is_binary(query.query)
      assert query.k == 10
      assert query.filters[:conversation_id] == "conv_123"
    end

    test "retrieve candidates step works correctly" do
      ctx =
        Context.new()
        |> Context.put_artifact(:history_query, %{
          query: "project status",
          filters: %{conversation_id: "conv_123"},
          k: 5
        })

      {:ok, updated_ctx, output} = RetrieveCandidatesStep.run(ctx, %{}, %{})

      candidates = Context.get_artifact(updated_ctx, :history_candidates)
      assert is_list(candidates)
      assert length(candidates) > 0
      assert output.candidates_found > 0
    end

    test "rerank candidates step works correctly" do
      candidates = [
        %{
          content: "Project status update",
          score: 0.8,
          metadata: %{timestamp: DateTime.utc_now()}
        },
        %{content: "Another message", score: 0.6, metadata: %{timestamp: DateTime.utc_now()}}
      ]

      ctx =
        Context.new()
        |> Context.put_artifact(:history_candidates, candidates)

      {:ok, updated_ctx, output} = RerankCandidatesStep.run(ctx, %{}, %{})

      top_candidates = Context.get_artifact(updated_ctx, :history_top)
      assert is_list(top_candidates)
      assert length(top_candidates) <= length(candidates)
      assert output.reranked_count > 0
    end

    test "compose context step works correctly" do
      candidates = [
        %{
          content: "Project status is good",
          score: 0.8,
          metadata: %{timestamp: DateTime.utc_now()}
        }
      ]

      ctx =
        Context.new()
        |> Context.put_artifact(:history_candidates, candidates)

      {:ok, updated_ctx, output} = ComposeContextStep.run(ctx, %{}, %{})

      context = Context.get_artifact(updated_ctx, :history_context)
      items_used = Context.get_artifact(updated_ctx, :history_items_used)

      assert is_binary(context)
      assert String.contains?(context, "Project status is good")
      assert items_used == 1
      assert output.context_created == true
    end

    test "done step works correctly" do
      ctx =
        Context.new()
        |> Context.put_artifact(:history_context, "Some context")
        |> Context.put_artifact(:history_items_used, 2)

      {:ok, updated_ctx, output} = DoneStep.run(ctx, %{}, %{})

      final_output = Context.get_artifact(updated_ctx, :final_output)
      assert final_output.history_context == "Some context"
      assert final_output.history_items_used == 2
      assert output.workflow_completed == true
    end
  end

  describe "workflow predicate functions" do
    test "candidates_not_empty works correctly" do
      ctx_with_candidates = %{artifacts: %{history_candidates: [%{content: "test"}]}}
      ctx_empty = %{artifacts: %{history_candidates: []}}
      ctx_nil = %{artifacts: %{}}

      assert HistoryWorkflow.candidates_not_empty(ctx_with_candidates) == true
      assert HistoryWorkflow.candidates_not_empty(ctx_empty) == false
      assert HistoryWorkflow.candidates_not_empty(ctx_nil) == false
    end

    test "candidates_empty works correctly" do
      ctx_with_candidates = %{artifacts: %{history_candidates: [%{content: "test"}]}}
      ctx_empty = %{artifacts: %{history_candidates: []}}

      assert HistoryWorkflow.candidates_empty(ctx_with_candidates) == false
      assert HistoryWorkflow.candidates_empty(ctx_empty) == true
    end
  end
end
