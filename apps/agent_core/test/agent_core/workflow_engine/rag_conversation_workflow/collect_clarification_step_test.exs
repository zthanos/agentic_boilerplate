defmodule AgentCore.WorkflowEngine.RagConversationWorkflow.CollectClarificationStepTest do
  use ExUnit.Case, async: true

  alias AgentCore.WorkflowEngine.RagConversationWorkflow.CollectClarificationStep
  alias AgentCore.WorkflowEngine.Context

  describe "id/0" do
    test "returns correct step id" do
      assert CollectClarificationStep.id() == :collect_clarification
    end
  end

  describe "run/3" do
    setup do
      # Create a basic context with clarification questions and enhanced prompt
      ctx = %Context{
        decisions: %{},
        artifacts: %{
          clarification_questions: [
            "What specific aspect would you like me to focus on?",
            "Are you referring to the recent changes or the overall system?"
          ],
          enhanced_prompt:
            "Original enhanced prompt with historical context about the user's project."
        },
        debug: %{},
        meta: %{},
        events: []
      }

      input = %{
        user_message: "Help me with the project",
        profile: create_mock_profile(),
        overrides: %{}
      }

      opts = %{
        simulated_clarification_responses: [
          "I want to focus on the performance optimization aspect.",
          "I'm referring to the recent changes made last week."
        ]
      }

      %{ctx: ctx, input: input, opts: opts}
    end

    test "handles missing clarification questions gracefully", %{input: input, opts: opts} do
      # Context without clarification questions
      ctx = %Context{
        decisions: %{},
        artifacts: %{
          enhanced_prompt: "Original enhanced prompt"
        },
        debug: %{},
        meta: %{},
        events: []
      }

      {:ok, updated_ctx, output} = CollectClarificationStep.run(ctx, input, opts)

      # Should fallback to original enhanced prompt
      assert Context.get_artifact(updated_ctx, :final_enhanced_prompt) ==
               "Original enhanced prompt"

      assert Context.get_artifact(updated_ctx, :clarification_responses) == []

      # Verify error handling
      assert output.clarification_collected == false
      assert output.fallback_used == true
      assert output.error == "no_clarification_questions"
    end

    test "handles missing profile gracefully", %{ctx: ctx, opts: opts} do
      input_without_profile = %{
        user_message: "Help me with the project",
        profile: nil,
        overrides: %{}
      }

      {:ok, updated_ctx, output} = CollectClarificationStep.run(ctx, input_without_profile, opts)

      # Should fallback to original enhanced prompt
      original_prompt = Context.get_artifact(ctx, :enhanced_prompt)
      assert Context.get_artifact(updated_ctx, :final_enhanced_prompt) == original_prompt

      # Verify error handling
      assert output.clarification_collected == false
      assert output.fallback_used == true
      assert output.error == "no_profile"
    end

    test "handles empty clarification questions list", %{input: input, opts: opts} do
      ctx = %Context{
        decisions: %{},
        artifacts: %{
          clarification_questions: [],
          enhanced_prompt: "Original enhanced prompt"
        },
        debug: %{},
        meta: %{},
        events: []
      }

      {:ok, updated_ctx, output} = CollectClarificationStep.run(ctx, input, opts)

      # Should fallback to original enhanced prompt
      assert Context.get_artifact(updated_ctx, :final_enhanced_prompt) ==
               "Original enhanced prompt"

      assert Context.get_artifact(updated_ctx, :clarification_responses) == []

      # Verify error handling
      assert output.clarification_collected == false
      assert output.fallback_used == true
      assert output.error == "no_clarification_questions"
      assert output.questions_count == 0
    end

    test "handles missing enhanced prompt gracefully", %{input: input, opts: opts} do
      ctx = %Context{
        decisions: %{},
        artifacts: %{
          clarification_questions: ["What do you mean?"]
        },
        debug: %{},
        meta: %{},
        events: []
      }

      input_without_profile = Map.put(input, :profile, nil)
      {:ok, updated_ctx, output} = CollectClarificationStep.run(ctx, input_without_profile, opts)

      # Should use user message as fallback when no enhanced prompt
      user_message = Map.get(input, :user_message, "")
      assert Context.get_artifact(updated_ctx, :final_enhanced_prompt) == user_message
      assert output.original_prompt_length == 0
    end

    test "handles nil user message gracefully", %{ctx: ctx, opts: opts} do
      input_with_nil_message = %{
        user_message: nil,
        # Use nil profile to avoid LLM calls
        profile: nil,
        overrides: %{}
      }

      {:ok, updated_ctx, output} = CollectClarificationStep.run(ctx, input_with_nil_message, opts)

      # Should handle nil message gracefully
      assert Context.get_artifact(updated_ctx, :final_enhanced_prompt) != nil
      assert output.original_message_length == 0
      # Due to nil profile
      assert output.clarification_collected == false
    end

    test "generates default clarification responses when none provided", %{ctx: ctx, opts: _opts} do
      input_without_profile = %{
        user_message: "Help me with the project",
        # Use nil profile to test fallback behavior
        profile: nil,
        overrides: %{}
      }

      # No simulated responses
      opts_without_responses = %{}

      {:ok, updated_ctx, output} =
        CollectClarificationStep.run(ctx, input_without_profile, opts_without_responses)

      # Should fallback due to no profile, but still track questions
      assert output.clarification_collected == false
      assert output.fallback_used == true
      assert output.questions_count == 2
      assert output.responses_count == 0
    end

    test "preserves original context structure", %{ctx: ctx, input: input, opts: opts} do
      input_without_profile = Map.put(input, :profile, nil)

      {:ok, updated_ctx, output} = CollectClarificationStep.run(ctx, input_without_profile, opts)

      # Verify context structure is preserved
      assert updated_ctx.decisions == ctx.decisions
      assert updated_ctx.debug == ctx.debug
      assert updated_ctx.meta == ctx.meta
      assert updated_ctx.events == ctx.events

      # Verify new artifacts are added
      assert Map.has_key?(updated_ctx.artifacts, :final_enhanced_prompt)
      assert Map.has_key?(updated_ctx.artifacts, :clarification_responses)

      # Verify output has required fields
      assert Map.has_key?(output, :clarification_collected)
      assert Map.has_key?(output, :questions_count)
      assert Map.has_key?(output, :responses_count)
      assert Map.has_key?(output, :final_prompt_length)
      assert Map.has_key?(output, :original_prompt_length)
      assert Map.has_key?(output, :original_message_length)
    end
  end

  # Helper function to create a mock profile
  defp create_mock_profile do
    %{
      id: "test_profile",
      name: "Test Profile",
      provider: "test_provider"
    }
  end
end
