defmodule AgentWeb.WorkflowValidatorDemo do
  @moduledoc """
  Demonstration script for the WorkflowValidator functionality.

  This module provides examples of how to use the WorkflowValidator
  to run automated validation tests against agents.
  """

  alias AgentWeb.WorkflowValidator
  alias AgentWeb.AgentSeeder

  @doc """
  Runs a complete validation demonstration.

  This function demonstrates:
  1. Seeding test agents
  2. Running validation tests
  3. Analyzing results
  4. Reporting outcomes
  """
  def run_demo do
    IO.puts("=== Workflow Validator Demonstration ===\n")

    # Step 1: Seed test agents
    IO.puts("1. Seeding test agents...")

    case AgentSeeder.seed_test_agents() do
      {:ok, agents} ->
        IO.puts("   ✓ Successfully seeded #{length(agents)} test agent(s)")
        agent = List.first(agents)
        run_validation_demo(agent.id)

      {:error, reason} ->
        IO.puts("   ✗ Failed to seed test agents: #{reason}")
        IO.puts("   → This is expected in test environments without LM Studio")
        demonstrate_validation_logic()
    end
  end

  defp run_validation_demo(agent_id) do
    IO.puts("\n2. Running validation tests...")

    case WorkflowValidator.run_validation_tests(agent_id: agent_id) do
      {:ok, report} ->
        display_validation_report(report)

      {:error, reason} ->
        IO.puts("   ✗ Validation failed: #{reason}")
        IO.puts("   → This may be due to LM Studio unavailability")
    end
  end

  defp display_validation_report(report) do
    IO.puts("   ✓ Validation completed successfully")
    IO.puts("\n=== Validation Report ===")
    IO.puts("Total Tests: #{report.total_tests}")
    IO.puts("Passed: #{report.passed}")
    IO.puts("Failed: #{report.failed}")
    IO.puts("Execution Time: #{report.execution_time_ms}ms")

    IO.puts("\n=== Test Results ===")

    Enum.each(report.results, fn result ->
      status_icon = if result.status == :passed, do: "✓", else: "✗"
      IO.puts("#{status_icon} #{result.test_name}")
      IO.puts("   Status: #{result.status}")
      IO.puts("   Time: #{result.execution_time_ms}ms")
      IO.puts("   Details: #{result.details}")

      if length(result.responses) > 0 do
        IO.puts("   Responses:")

        result.responses
        |> Enum.with_index()
        |> Enum.each(fn {response, index} ->
          IO.puts("     #{index + 1}. #{String.slice(response, 0, 80)}...")
        end)
      end

      IO.puts("")
    end)
  end

  defp demonstrate_validation_logic do
    IO.puts("\n2. Demonstrating validation logic...")

    test_responses = [
      {"Yes, your name is Thanos. How can I help you?", "Valid response"},
      {"I remember you said your name is Thanos earlier.", "Valid context retention"},
      {"I don't remember your name, could you clarify?", "Invalid - no context"},
      {"Could you be more specific about what you mean?", "Invalid - clarification"}
    ]

    IO.puts("\n=== Response Validation Examples ===")

    Enum.each(test_responses, fn {response, description} ->
      validation = validate_response_example(response)
      status_icon = if validation.valid?, do: "✓", else: "✗"

      IO.puts("#{status_icon} #{description}")
      IO.puts("   Response: \"#{response}\"")
      IO.puts("   Result: #{validation.details}")
      IO.puts("")
    end)
  end

  # Helper function that mimics the validation logic from WorkflowValidator
  defp validate_response_example(response) do
    response_lower = String.downcase(response)
    contains_thanos = String.contains?(response_lower, "thanos")

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
        %{valid?: true, details: "Contains 'Thanos' and is not a clarification"}

      not contains_thanos ->
        %{valid?: false, details: "Does not contain 'Thanos'"}

      is_clarification ->
        %{valid?: false, details: "Is a clarification request"}

      true ->
        %{valid?: false, details: "Unexpected validation state"}
    end
  end

  @doc """
  Demonstrates the Thanos context retention test specifically.
  """
  def demo_thanos_test do
    IO.puts("=== Thanos Context Retention Test Demo ===\n")

    IO.puts("Test Scenario:")
    IO.puts("1. Send: 'My name is Thanos, what is your name?'")
    IO.puts("2. Send: 'Do you know my name?'")
    IO.puts("3. Validate: Response contains 'Thanos' and is not clarification\n")

    IO.puts("Expected Behavior:")
    IO.puts("- Agent should remember the name 'Thanos' from the first message")
    IO.puts("- Agent should respond to the second question with the remembered name")
    IO.puts("- Response should not be a clarification request\n")

    IO.puts("Validation Criteria:")
    IO.puts("✓ Response contains the word 'Thanos'")
    IO.puts("✓ Response is not a clarification request")
    IO.puts("✗ Response asks for clarification")
    IO.puts("✗ Response does not mention 'Thanos'\n")

    demonstrate_validation_logic()
  end

  @doc """
  Shows the test database isolation features.
  """
  def demo_database_isolation do
    IO.puts("=== Database Isolation Demo ===\n")

    config = Application.get_env(:agent_infra, AgentInfra.Repo)
    database = Keyword.get(config, :database, "unknown")

    IO.puts("Current Database: #{database}")

    if String.contains?(database, "test") do
      IO.puts("✓ Running against test database - isolation confirmed")
      IO.puts("  → Test data will not interfere with development data")
      IO.puts("  → Database will be cleaned up after tests")
    else
      IO.puts("✗ Not running against test database")
      IO.puts("  → Validation tests should only run in test environment")
    end

    IO.puts("\nIsolation Features:")
    IO.puts("- Separate test database for validation runs")
    IO.puts("- Automatic cleanup after test completion")
    IO.puts("- No interference with development or production data")
    IO.puts("- Safe to run multiple validation sessions concurrently")
  end
end
