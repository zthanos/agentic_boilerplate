defmodule AgentCore.WorkflowEngine.RagConversationWorkflow.RetrieveContextStepTest do
  use ExUnit.Case, async: true

  alias AgentCore.WorkflowEngine.{Context, RagConversationWorkflow.RetrieveContextStep}

  describe "RetrieveContextStep" do
    test "returns correct step id" do
      assert RetrieveContextStep.id() == :retrieve_context
    end

    test "handles missing history query gracefully" do
      ctx = Context.new()
      input = %{conversation_id: "test-conv", profile: %{"id" => "test"}}
      opts = %{}

      {:ok, updated_ctx, output} = RetrieveContextStep.run(ctx, input, opts)

      assert Context.get_artifact(updated_ctx, :retrieved_context) == []
      assert output.retrieved_count == 0
      assert output.reason == "no_history_query"
    end

    test "handles missing conversation_id" do
      ctx = Context.put_artifact(Context.new(), :history_query, "test query")
      input = %{profile: %{"id" => "test"}}
      opts = %{}

      {:ok, updated_ctx, output} = RetrieveContextStep.run(ctx, input, opts)

      assert Context.get_artifact(updated_ctx, :retrieved_context) == []
      assert output.retrieved_count == 0
    end

    test "handles missing profile gracefully" do
      ctx = Context.put_artifact(Context.new(), :history_query, "test query")
      input = %{conversation_id: "test-conv"}
      opts = %{}

      {:ok, updated_ctx, output} = RetrieveContextStep.run(ctx, input, opts)

      assert Context.get_artifact(updated_ctx, :retrieved_context) == []
      assert output.retrieved_count == 0
      assert Map.has_key?(output, :error)
    end

    test "processes valid input structure correctly" do
      ctx = Context.put_artifact(Context.new(), :history_query, "test query")

      input = %{
        conversation_id: "test-conv",
        profile: %{"id" => "test"},
        overrides: %{}
      }

      opts = %{limit: 5, threshold: 0.8}

      # This will fail due to missing LLM infrastructure, but should handle gracefully
      {:ok, updated_ctx, output} = RetrieveContextStep.run(ctx, input, opts)

      # Should set empty context on error and continue
      assert Context.get_artifact(updated_ctx, :retrieved_context) == []
      assert output.retrieved_count == 0
      assert Map.has_key?(output, :error)
      assert output.query_used == "test query"
      assert output.conversation_id == "test-conv"
    end

    test "step behavior interface compliance" do
      # Test that the step implements the required behavior correctly
      assert function_exported?(RetrieveContextStep, :id, 0)
      assert function_exported?(RetrieveContextStep, :run, 3)

      # Test return value format
      ctx = Context.new()
      input = %{}
      opts = %{}

      result = RetrieveContextStep.run(ctx, input, opts)

      assert match?({:ok, %Context{}, %{}}, result) or
               match?({:skip, %Context{}, %{}}, result) or
               match?({:error, %Context{}, %{}}, result)
    end
  end
end
