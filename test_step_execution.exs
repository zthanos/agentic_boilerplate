# Simple test to verify step module execution
# Run this in the Docker container to test the step directly

# Test if the module can be loaded and called
try do
  # Test module loading
  IO.puts("Testing module loading...")
  module = AgentCore.WorkflowEngine.RagConversationWorkflow.GenerateQueryStep
  IO.puts("Module loaded: #{inspect(module)}")

  # Test if the module implements the required functions
  IO.puts("Checking if module implements required functions...")
  IO.puts("Has id/0: #{function_exported?(module, :id, 0)}")
  IO.puts("Has run/3: #{function_exported?(module, :run, 3)}")

  if function_exported?(module, :id, 0) do
    IO.puts("Step ID: #{module.id()}")
  end

  # Test basic context creation
  IO.puts("Testing context creation...")
  ctx = AgentCore.WorkflowEngine.Context.new(%{
    run_id: "test_run",
    trace_id: "test_trace"
  })
  IO.puts("Context created: #{inspect(ctx)}")

  # Test input
  input = %{
    user_message: "Hello, what is your name?",
    conversation_id: "test_conversation",
    profile: nil,  # This should trigger the no_profile path
    overrides: %{}
  }

  opts = %{
    system_prompt: "Test prompt",
    max_query_length: 200,
    fallback_behavior: :skip_history
  }

  IO.puts("Testing step execution with nil profile (should skip)...")
  result = module.run(ctx, input, opts)
  IO.puts("Result: #{inspect(result)}")

rescue
  e ->
    IO.puts("Error: #{Exception.message(e)}")
    IO.puts("Stacktrace:")
    IO.inspect(__STACKTRACE__)
end
