#!/usr/bin/env elixir

# Debug script to test the RAG conversation workflow execution
# This script will help us understand why the workflow is failing

# Load the application
Mix.install([
  {:jason, "~> 1.4"}
])

# Simulate the workflow execution
defmodule WorkflowDebugger do
  def test_workflow_execution do
    IO.puts("=== RAG Conversation Workflow Debug Test ===")

    # Test input similar to what the agent executor would provide
    test_input = %{
      user_message: "Hello, what is your name?",
      conversation_id: "test_conversation_123",
      profile: %{
        id: "req_llm",
        provider: :openai,
        model: "gpt-3.5-turbo"
      },
      overrides: %{},
      user_context: %{
        agent_id: "test_agent",
        agent_version: 1,
        system_prompt: "You are a helpful AI assistant."
      }
    }

    IO.puts("Test input prepared:")
    IO.inspect(test_input, pretty: true)

    # Test the generate query step directly
    IO.puts("\n=== Testing GenerateQueryStep directly ===")

    try do
      # Create a mock context
      ctx = %{
        run_id: "test_run_123",
        trace_id: "test_trace_123",
        artifacts: %{},
        decisions: %{}
      }

      IO.puts("Mock context created:")
      IO.inspect(ctx, pretty: true)

      # Test step options
      step_opts = %{
        system_prompt: "Generate search queries for conversation history",
        max_query_length: 200,
        fallback_behavior: :skip_history
      }

      IO.puts("Step options:")
      IO.inspect(step_opts, pretty: true)

      IO.puts("\nThis would be the point where we call the step...")
      IO.puts("Since we can't load the full application context here,")
      IO.puts("we need to check the logs from the actual execution.")

    rescue
      e ->
        IO.puts("Error in test: #{Exception.message(e)}")
        IO.puts("Stacktrace:")
        IO.inspect(__STACKTRACE__, pretty: true)
    end
  end
end

WorkflowDebugger.test_workflow_execution()
