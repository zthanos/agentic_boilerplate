defmodule AgentCore.WorkflowEngine.RagConversationWorkflow.EnhancePromptStepTest do
  use ExUnit.Case, async: true

  alias AgentCore.WorkflowEngine.RagConversationWorkflow.EnhancePromptStep
  alias AgentCore.WorkflowEngine.Context

  describe "id/0" do
    test "returns the correct step identifier" do
      assert EnhancePromptStep.id() == :enhance_prompt
    end
  end

  describe "run/3" do
    test "enhances prompt with retrieved context" do
      # Setup context with retrieved context
      ctx = Context.new()

      context_items = [
        %{
          content: "Previous discussion about authentication",
          score: 0.85,
          metadata: %{timestamp: "2024-01-01T10:00:00Z"}
        },
        %{
          content: "Database configuration details",
          score: 0.72,
          metadata: %{timestamp: "2024-01-01T09:30:00Z"}
        }
      ]

      ctx = Context.put_artifact(ctx, :retrieved_context, context_items)

      input = %{user_message: "How do I set up the auth system?"}
      opts = %{}

      # Execute step
      {:ok, updated_ctx, output} = EnhancePromptStep.run(ctx, input, opts)

      # Verify enhanced prompt was created
      enhanced_prompt = Context.get_artifact(updated_ctx, :enhanced_prompt)
      assert is_binary(enhanced_prompt)
      assert String.contains?(enhanced_prompt, "How do I set up the auth system?")
      assert String.contains?(enhanced_prompt, "Previous discussion about authentication")
      assert String.contains?(enhanced_prompt, "Database configuration details")

      # Verify output structure
      assert output.enhanced == true
      assert output.context_items_used == 2
      assert output.original_length == String.length("How do I set up the auth system?")
      assert output.enhanced_length > output.original_length
    end

    test "handles empty context gracefully" do
      ctx = Context.new()
      ctx = Context.put_artifact(ctx, :retrieved_context, [])

      input = %{user_message: "Hello world"}
      opts = %{}

      {:ok, updated_ctx, output} = EnhancePromptStep.run(ctx, input, opts)

      # Should return original message when no context
      enhanced_prompt = Context.get_artifact(updated_ctx, :enhanced_prompt)
      assert enhanced_prompt == "Hello world"

      # Verify output
      assert output.enhanced == true
      assert output.context_items_used == 0
    end

    test "handles missing context artifact" do
      ctx = Context.new()
      # No retrieved_context artifact set

      input = %{user_message: "Test message"}
      opts = %{}

      {:ok, updated_ctx, output} = EnhancePromptStep.run(ctx, input, opts)

      # Should return original message when no context artifact
      enhanced_prompt = Context.get_artifact(updated_ctx, :enhanced_prompt)
      assert enhanced_prompt == "Test message"

      # Verify output
      assert output.enhanced == true
      assert output.context_items_used == 0
    end

    test "filters context by minimum score" do
      ctx = Context.new()

      context_items = [
        %{content: "High relevance item", score: 0.9, metadata: %{}},
        %{content: "Low relevance item", score: 0.1, metadata: %{}},
        %{content: "Medium relevance item", score: 0.5, metadata: %{}}
      ]

      ctx = Context.put_artifact(ctx, :retrieved_context, context_items)

      input = %{user_message: "Test query"}
      opts = %{min_context_score: 0.4}

      {:ok, updated_ctx, output} = EnhancePromptStep.run(ctx, input, opts)

      enhanced_prompt = Context.get_artifact(updated_ctx, :enhanced_prompt)

      # Should include high and medium relevance items
      assert String.contains?(enhanced_prompt, "High relevance item")
      assert String.contains?(enhanced_prompt, "Medium relevance item")
      # Should not include low relevance item
      refute String.contains?(enhanced_prompt, "Low relevance item")

      # Should report 2 items used (after filtering)
      assert output.context_items_used == 2
    end

    test "limits number of context items" do
      ctx = Context.new()

      context_items =
        Enum.map(1..10, fn i ->
          %{
            content: "Context item #{i}",
            score: 0.8,
            metadata: %{}
          }
        end)

      ctx = Context.put_artifact(ctx, :retrieved_context, context_items)

      input = %{user_message: "Test query"}
      opts = %{max_context_items: 3}

      {:ok, updated_ctx, output} = EnhancePromptStep.run(ctx, input, opts)

      # Should only use 3 items despite 10 being available
      assert output.context_items_used == 3

      enhanced_prompt = Context.get_artifact(updated_ctx, :enhanced_prompt)
      assert String.contains?(enhanced_prompt, "Context item 1")
      assert String.contains?(enhanced_prompt, "Context item 2")
      assert String.contains?(enhanced_prompt, "Context item 3")
    end

    test "truncates long content" do
      ctx = Context.new()
      long_content = String.duplicate("a", 1000)

      context_items = [
        %{content: long_content, score: 0.8, metadata: %{}}
      ]

      ctx = Context.put_artifact(ctx, :retrieved_context, context_items)

      input = %{user_message: "Test query"}
      opts = %{max_content_length: 100}

      {:ok, updated_ctx, output} = EnhancePromptStep.run(ctx, input, opts)

      enhanced_prompt = Context.get_artifact(updated_ctx, :enhanced_prompt)

      # Should contain truncated content with ellipsis
      assert String.contains?(enhanced_prompt, "...")
      # Should not contain the full long content
      refute String.contains?(enhanced_prompt, String.duplicate("a", 500))
    end

    test "includes context scores when configured" do
      ctx = Context.new()

      context_items = [
        %{content: "Test content", score: 0.85, metadata: %{}}
      ]

      ctx = Context.put_artifact(ctx, :retrieved_context, context_items)

      input = %{user_message: "Test query"}
      opts = %{include_context_scores: true}

      {:ok, updated_ctx, output} = EnhancePromptStep.run(ctx, input, opts)

      enhanced_prompt = Context.get_artifact(updated_ctx, :enhanced_prompt)

      # Should include relevance score
      assert String.contains?(enhanced_prompt, "relevance: 0.85")
    end
  end
end
