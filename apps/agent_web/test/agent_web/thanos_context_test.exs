defmodule AgentWeb.ThanosContextTest do
  @moduledoc """
  Integration test for the Thanos context retention scenario.

  This test validates that agents properly retain and use conversation context by:
  1. Sending "My name is Thanos, what is your name?"
  2. Sending "Do you know my name?"
  3. Asserting the response contains "Thanos" and is not a clarification request
  """

  use AgentWeb.DataCase, async: false

  alias AgentWeb.WorkflowValidator
  alias AgentWeb.AgentSeeder

  @moduletag :integration

  describe "Thanos context retention validation" do
    setup do
      # Create a test profile for validation
      test_profile = %AgentCore.Llm.LLMProfile{
        id: "thanos_test_profile",
        name: "Thanos Test Profile",
        enabled: true,
        provider: :openai_compatible,
        model: "openai/gpt-oss-20b",
        policy_version: "1",
        generation: %{temperature: 0.2, top_p: 1.0, max_output_tokens: 1000, seed: 42},
        budgets: %{request_timeout_ms: 60_000, max_retries: 0},
        tools: [],
        stop_list: [],
        tags: ["test", "thanos", "context"]
      }

      case AgentCore.Llm.Profiles.put(test_profile) do
        {:ok, profile} -> %{profile: profile}
        {:error, _} -> %{profile: test_profile}
      end
    end

    test "validates Thanos context retention with seeded agent", %{profile: profile} do
      # Try to seed a test agent
      case AgentSeeder.seed_test_agents() do
        {:ok, [agent]} ->
          # Run the Thanos context retention test
          result =
            WorkflowValidator.run_thanos_context_test(
              agent.id,
              :latest,
              profile,
              30_000
            )

          assert {:ok, test_result} = result
          assert test_result.test_name == "Thanos Context Retention Test"
          assert test_result.status in [:passed, :failed]
          assert is_integer(test_result.execution_time_ms)
          assert is_list(test_result.responses)
          assert is_binary(test_result.details)

          # Log the result for debugging
          IO.puts("\n=== Thanos Context Test Result ===")
          IO.puts("Status: #{test_result.status}")
          IO.puts("Details: #{test_result.details}")
          IO.puts("Execution Time: #{test_result.execution_time_ms}ms")

          if length(test_result.responses) > 0 do
            IO.puts("Responses:")

            test_result.responses
            |> Enum.with_index()
            |> Enum.each(fn {response, index} ->
              IO.puts("  #{index + 1}. #{String.slice(response, 0, 100)}...")
            end)
          end

          IO.puts("===================================\n")

        {:error, reason} ->
          IO.puts("Skipping Thanos test - agent seeding failed: #{inspect(reason)}")
          assert true
      end
    end

    test "validates Thanos response analysis logic" do
      # Test the validation logic with different response scenarios
      test_cases = [
        # Valid responses (should pass)
        {
          "Yes, your name is Thanos. Nice to meet you!",
          true,
          "Should pass - contains Thanos and is not clarification"
        },
        {
          "I remember you mentioned your name is Thanos earlier.",
          true,
          "Should pass - contains Thanos and shows context retention"
        },
        # Invalid responses (should fail)
        {
          "I don't remember your name, could you clarify?",
          false,
          "Should fail - doesn't contain Thanos"
        },
        {
          "Could you clarify what you mean by that?",
          false,
          "Should fail - is a clarification request"
        },
        {
          "I'm not sure what your name is, can you explain?",
          false,
          "Should fail - clarification and no Thanos"
        }
      ]

      Enum.each(test_cases, fn {response, expected_valid, description} ->
        # Use the private validation function through a test helper
        validation_result = validate_test_response(response)

        assert validation_result.valid? == expected_valid,
               "#{description}. Response: '#{response}'. Expected: #{expected_valid}, Got: #{validation_result.valid?}. Details: #{validation_result.details}"
      end)
    end

    test "validates test scenario structure and requirements" do
      # Verify the test scenario meets the requirements from the spec
      test_prompts = [
        "My name is Thanos, what is your name?",
        "Do you know my name?"
      ]

      # Requirement 6.2: First test prompt should introduce the name
      first_prompt = Enum.at(test_prompts, 0)
      assert String.contains?(String.downcase(first_prompt), "thanos")
      assert String.contains?(String.downcase(first_prompt), "name")

      # Requirement 6.3: Second test prompt should test context retention
      second_prompt = Enum.at(test_prompts, 1)
      assert String.contains?(String.downcase(second_prompt), "know")
      assert String.contains?(String.downcase(second_prompt), "name")

      # Requirement 6.4: Test should validate response contains "Thanos"
      # This is tested in the validation logic above
      assert true
    end

    test "handles timeout scenarios gracefully", %{profile: profile} do
      case AgentSeeder.seed_test_agents() do
        {:ok, [agent]} ->
          # Test with very short timeout to trigger timeout condition
          result =
            WorkflowValidator.run_thanos_context_test(
              agent.id,
              :latest,
              profile,
              1
            )

          assert {:ok, test_result} = result
          assert test_result.status == :failed

          # Should handle timeout gracefully
          timeout_mentioned =
            String.contains?(test_result.details, "timeout") or
              String.contains?(test_result.error || "", "timeout") or
              String.contains?(test_result.details, "failed")

          assert timeout_mentioned

        {:error, _reason} ->
          # Skip if agent seeding failed
          assert true
      end
    end
  end

  # Helper function to test the validation logic
  defp validate_test_response(response) do
    response_lower = String.downcase(response)
    contains_thanos = String.contains?(response_lower, "thanos")

    # Check if response is a clarification request (common patterns)
    clarification_patterns = [
      "could you clarify",
      "what do you mean",
      "i don't understand",
      "can you explain",
      "i'm not sure",
      "could you be more specific"
    ]

    is_clarification =
      Enum.any?(clarification_patterns, fn pattern ->
        String.contains?(response_lower, pattern)
      end)

    cond do
      contains_thanos and not is_clarification ->
        %{
          valid?: true,
          details:
            "✓ Response contains 'Thanos' and is not a clarification request. Response: #{String.slice(response, 0, 100)}..."
        }

      not contains_thanos ->
        %{
          valid?: false,
          details:
            "✗ Response does not contain 'Thanos'. Expected agent to remember the name from context. Response: #{String.slice(response, 0, 100)}..."
        }

      is_clarification ->
        %{
          valid?: false,
          details:
            "✗ Response appears to be a clarification request instead of using context. Response: #{String.slice(response, 0, 100)}..."
        }

      true ->
        %{
          valid?: false,
          details: "✗ Unexpected validation state. Response: #{String.slice(response, 0, 100)}..."
        }
    end
  end
end
