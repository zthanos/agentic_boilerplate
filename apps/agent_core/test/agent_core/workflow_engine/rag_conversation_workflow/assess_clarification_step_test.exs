defmodule AgentCore.WorkflowEngine.RagConversationWorkflow.AssessClarificationStepTest do
  use ExUnit.Case, async: true

  alias AgentCore.WorkflowEngine.RagConversationWorkflow.AssessClarificationStep
  alias AgentCore.WorkflowEngine.Context

  describe "id/0" do
    test "returns the correct step identifier" do
      assert AssessClarificationStep.id() == :assess_clarification
    end
  end

  describe "run/3" do
    test "sets needs_clarification to false when no profile provided" do
      ctx = Context.new()
      ctx = Context.put_artifact(ctx, :enhanced_prompt, "Test enhanced prompt")

      input = %{user_message: "Test message"}
      opts = %{}

      {:ok, updated_ctx, output} = AssessClarificationStep.run(ctx, input, opts)

      # Should default to false when no profile
      needs_clarification = Context.get_decision(updated_ctx, :needs_clarification)
      assert needs_clarification == false

      # Verify output structure
      assert output.needs_clarification == false
      assert output.assessment_completed == false
      assert output.fallback_used == true
      assert is_binary(output.error)
    end

    test "sets needs_clarification to false when no enhanced prompt" do
      ctx = Context.new()
      # No enhanced_prompt artifact set

      input = %{
        user_message: "Test message",
        profile: %{id: "test-profile"}
      }

      opts = %{}

      {:ok, updated_ctx, output} = AssessClarificationStep.run(ctx, input, opts)

      # Should default to false when no enhanced prompt
      needs_clarification = Context.get_decision(updated_ctx, :needs_clarification)
      assert needs_clarification == false

      # Verify output structure
      assert output.needs_clarification == false
      assert output.assessment_completed == true
      assert Map.has_key?(output, :clarification_data)
    end

    test "sets needs_clarification to false when enhanced prompt is empty" do
      ctx = Context.new()
      ctx = Context.put_artifact(ctx, :enhanced_prompt, "")

      input = %{
        user_message: "Test message",
        profile: %{id: "test-profile"}
      }

      opts = %{}

      {:ok, updated_ctx, output} = AssessClarificationStep.run(ctx, input, opts)

      # Should default to false when enhanced prompt is empty
      needs_clarification = Context.get_decision(updated_ctx, :needs_clarification)
      assert needs_clarification == false

      # Verify output structure
      assert output.needs_clarification == false
      assert output.assessment_completed == true
    end

    test "handles missing user_message gracefully" do
      ctx = Context.new()
      ctx = Context.put_artifact(ctx, :enhanced_prompt, "Test enhanced prompt")

      # No profile provided, so no LLM execution
      input = %{}
      opts = %{}

      {:ok, updated_ctx, output} = AssessClarificationStep.run(ctx, input, opts)

      # Should handle missing user_message
      assert is_boolean(Context.get_decision(updated_ctx, :needs_clarification))
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

      {:ok, _updated_ctx, output} = AssessClarificationStep.run(ctx, input, opts)

      # Verify all required output fields are present
      assert Map.has_key?(output, :needs_clarification)
      assert Map.has_key?(output, :assessment_completed)
      assert Map.has_key?(output, :enhanced_prompt_length)
      assert Map.has_key?(output, :original_message_length)

      # Verify length calculations
      assert output.enhanced_prompt_length == String.length(enhanced_prompt)
      assert output.original_message_length == String.length(user_message)
    end

    test "preserves context state" do
      ctx = Context.new()
      ctx = Context.put_artifact(ctx, :enhanced_prompt, "Test prompt")
      ctx = Context.put_artifact(ctx, :other_data, "should be preserved")

      input = %{user_message: "Test"}
      opts = %{}

      {:ok, updated_ctx, _output} = AssessClarificationStep.run(ctx, input, opts)

      # Should preserve existing artifacts
      assert Context.get_artifact(updated_ctx, :enhanced_prompt) == "Test prompt"
      assert Context.get_artifact(updated_ctx, :other_data) == "should be preserved"

      # Should add the decision
      assert is_boolean(Context.get_decision(updated_ctx, :needs_clarification))
    end
  end

  describe "parse response handling" do
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

        {:ok, updated_ctx, output} = AssessClarificationStep.run(ctx, input, opts)

        # Should always return valid results
        assert is_boolean(Context.get_decision(updated_ctx, :needs_clarification))
        assert is_boolean(output.needs_clarification)
        assert is_boolean(output.assessment_completed)
        assert is_integer(output.enhanced_prompt_length)
        assert is_integer(output.original_message_length)
      end
    end
  end
end
