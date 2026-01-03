defmodule AgentCore.WorkflowEngine.RagConversationWorkflow.FinalResponseStepTest do
  use ExUnit.Case, async: true

  alias AgentCore.WorkflowEngine.RagConversationWorkflow.FinalResponseStep
  alias AgentCore.WorkflowEngine.Context

  describe "id/0" do
    test "returns the correct step identifier" do
      assert FinalResponseStep.id() == :final_response
    end
  end

  describe "run/3" do
    test "generates fallback response when no profile provided" do
      ctx = Context.new()
      ctx = Context.put_artifact(ctx, :enhanced_prompt, "Test enhanced prompt")

      input = %{user_message: "Test message"}
      opts = %{}

      {:ok, updated_ctx, output} = FinalResponseStep.run(ctx, input, opts)

      # Should generate fallback response when no profile
      final_response = Context.get_artifact(updated_ctx, :final_response)
      assert is_binary(final_response)
      assert String.contains?(final_response, "technical difficulties")

      response_metadata = Context.get_artifact(updated_ctx, :response_metadata)
      assert response_metadata.fallback_used == true
      assert is_binary(response_metadata.error)

      # Verify output structure
      assert output.response_generated == true
      assert output.fallback_used == true
      assert is_binary(output.error)
      assert is_integer(output.response_length)
      assert output.response_length > 0
    end

    test "generates fallback response when no enhanced prompt" do
      ctx = Context.new()
      # No enhanced_prompt artifact set

      input = %{
        user_message: "Test message",
        profile: %{id: "test-profile"}
      }

      opts = %{}

      {:ok, updated_ctx, output} = FinalResponseStep.run(ctx, input, opts)

      # Should generate fallback response when no enhanced prompt
      final_response = Context.get_artifact(updated_ctx, :final_response)
      assert is_binary(final_response)
      assert String.contains?(final_response, "technical difficulties")

      response_metadata = Context.get_artifact(updated_ctx, :response_metadata)
      assert response_metadata.fallback_used == true
      assert response_metadata.error == "no_enhanced_prompt"

      # Verify output structure
      assert output.response_generated == true
      assert output.fallback_used == true
      assert output.error == "no_enhanced_prompt"
    end

    test "generates fallback response when enhanced prompt is empty" do
      ctx = Context.new()
      ctx = Context.put_artifact(ctx, :enhanced_prompt, "")

      input = %{
        user_message: "Test message",
        profile: %{id: "test-profile"}
      }

      opts = %{}

      {:ok, updated_ctx, output} = FinalResponseStep.run(ctx, input, opts)

      # Should generate fallback response when enhanced prompt is empty
      final_response = Context.get_artifact(updated_ctx, :final_response)
      assert is_binary(final_response)
      assert String.contains?(final_response, "technical difficulties")

      response_metadata = Context.get_artifact(updated_ctx, :response_metadata)
      assert response_metadata.fallback_used == true
      assert response_metadata.error == "no_enhanced_prompt"
    end

    test "handles missing user_message gracefully" do
      ctx = Context.new()
      ctx = Context.put_artifact(ctx, :enhanced_prompt, "Test enhanced prompt")

      # No profile provided, so fallback will be used
      input = %{}
      opts = %{}

      {:ok, updated_ctx, output} = FinalResponseStep.run(ctx, input, opts)

      # Should handle missing user_message
      final_response = Context.get_artifact(updated_ctx, :final_response)
      assert is_binary(final_response)

      response_metadata = Context.get_artifact(updated_ctx, :response_metadata)
      assert is_map(response_metadata)

      assert is_map(output)
      assert output.original_message_length == 0
    end

    test "includes correct output structure" do
      ctx = Context.new()
      enhanced_prompt = "This is a test enhanced prompt with context"
      ctx = Context.put_artifact(ctx, :enhanced_prompt, enhanced_prompt)

      user_message = "Test user message"
      input = %{user_message: user_message}
      opts = %{}

      {:ok, updated_ctx, output} = FinalResponseStep.run(ctx, input, opts)

      # Verify all required output fields are present
      assert Map.has_key?(output, :response_generated)
      assert Map.has_key?(output, :response_length)
      assert Map.has_key?(output, :enhanced_prompt_length)
      assert Map.has_key?(output, :original_message_length)

      # Verify length calculations
      assert output.enhanced_prompt_length == String.length(enhanced_prompt)
      assert output.original_message_length == String.length(user_message)

      # Verify artifacts are set
      assert is_binary(Context.get_artifact(updated_ctx, :final_response))
      assert is_map(Context.get_artifact(updated_ctx, :response_metadata))
    end

    test "preserves context state" do
      ctx = Context.new()
      ctx = Context.put_artifact(ctx, :enhanced_prompt, "Test prompt")
      ctx = Context.put_artifact(ctx, :other_data, "should be preserved")

      input = %{user_message: "Test"}
      opts = %{}

      {:ok, updated_ctx, _output} = FinalResponseStep.run(ctx, input, opts)

      # Should preserve existing artifacts
      assert Context.get_artifact(updated_ctx, :enhanced_prompt) == "Test prompt"
      assert Context.get_artifact(updated_ctx, :other_data) == "should be preserved"

      # Should add the new artifacts
      assert is_binary(Context.get_artifact(updated_ctx, :final_response))
      assert is_map(Context.get_artifact(updated_ctx, :response_metadata))
    end

    test "applies response formatting options" do
      ctx = Context.new()
      ctx = Context.put_artifact(ctx, :enhanced_prompt, "Test prompt")

      input = %{user_message: "Test"}

      # Test with max response length
      opts = %{
        max_response_length: 50,
        fallback_template: "Short fallback: {user_message}"
      }

      {:ok, updated_ctx, output} = FinalResponseStep.run(ctx, input, opts)

      final_response = Context.get_artifact(updated_ctx, :final_response)
      assert is_binary(final_response)
      assert String.length(final_response) <= 50
      assert String.contains?(final_response, "Short fallback")
    end
  end

  describe "response handling" do
    test "handles various input formats gracefully" do
      ctx = Context.new()
      ctx = Context.put_artifact(ctx, :enhanced_prompt, "Test prompt")

      # Test with different input variations
      test_cases = [
        %{user_message: ""},
        %{user_message: nil},
        %{user_message: "Normal message"},
        # Very long message
        %{user_message: String.duplicate("a", 1000)}
      ]

      for test_input <- test_cases do
        input = Map.merge(test_input, %{})
        opts = %{}

        {:ok, updated_ctx, output} = FinalResponseStep.run(ctx, input, opts)

        # Should always return valid results
        assert is_binary(Context.get_artifact(updated_ctx, :final_response))
        assert is_map(Context.get_artifact(updated_ctx, :response_metadata))
        assert is_boolean(output.response_generated)
        assert is_integer(output.response_length)
        assert is_integer(output.enhanced_prompt_length)
        assert is_integer(output.original_message_length)
      end
    end

    test "handles custom fallback template" do
      ctx = Context.new()
      ctx = Context.put_artifact(ctx, :enhanced_prompt, "Test prompt")

      custom_template = "Custom error message for {user_message} at {timestamp}"
      input = %{user_message: "test query"}
      opts = %{fallback_template: custom_template}

      {:ok, updated_ctx, _output} = FinalResponseStep.run(ctx, input, opts)

      final_response = Context.get_artifact(updated_ctx, :final_response)
      assert String.contains?(final_response, "Custom error message")
      assert String.contains?(final_response, "test query")
    end

    test "applies content filters when configured" do
      ctx = Context.new()
      ctx = Context.put_artifact(ctx, :enhanced_prompt, "Test prompt")

      input = %{user_message: "Test"}

      opts = %{
        content_filters: [
          {:replace_pattern, "technical difficulties", "service issues"}
        ]
      }

      {:ok, updated_ctx, _output} = FinalResponseStep.run(ctx, input, opts)

      final_response = Context.get_artifact(updated_ctx, :final_response)
      assert String.contains?(final_response, "service issues")
      refute String.contains?(final_response, "technical difficulties")
    end
  end

  describe "metadata collection" do
    test "collects appropriate metadata for fallback responses" do
      ctx = Context.new()
      ctx = Context.put_artifact(ctx, :enhanced_prompt, "Test prompt")

      input = %{user_message: "Test"}
      opts = %{}

      {:ok, updated_ctx, _output} = FinalResponseStep.run(ctx, input, opts)

      response_metadata = Context.get_artifact(updated_ctx, :response_metadata)

      assert response_metadata.fallback_used == true
      assert is_binary(response_metadata.error)
      assert %DateTime{} = response_metadata.generation_time
    end

    test "includes generation metadata structure" do
      ctx = Context.new()
      ctx = Context.put_artifact(ctx, :enhanced_prompt, "Test prompt")

      input = %{user_message: "Test message"}
      opts = %{}

      {:ok, updated_ctx, output} = FinalResponseStep.run(ctx, input, opts)

      # Verify output includes generation metadata
      assert Map.has_key?(output, :generation_metadata)
      assert is_map(output.generation_metadata)

      # Verify response metadata artifact
      response_metadata = Context.get_artifact(updated_ctx, :response_metadata)
      assert is_map(response_metadata)
      assert Map.has_key?(response_metadata, :generation_time)
    end
  end
end
