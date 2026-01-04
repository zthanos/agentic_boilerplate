defmodule AgentWeb.WorkflowValidator do
  @moduledoc """
  Automated workflow validation system that validates agent behavior with predefined scenarios.

  This module provides functionality to:
  - Execute validation tests against isolated test database
  - Run predefined test scenarios like context retention tests
  - Report detailed test results and assertion failures
  - Integrate with LM Studio for realistic language model testing
  """

  alias AgentRuntime.Llm.AgentExecutor
  alias AgentCore.Llm.Profiles
  alias AgentWeb.Llm.InputMapper

  @type validation_result :: %{
          test_name: String.t(),
          status: :passed | :failed,
          details: String.t(),
          execution_time_ms: integer(),
          responses: [String.t()],
          error: String.t() | nil
        }

  @type validation_report :: %{
          total_tests: integer(),
          passed: integer(),
          failed: integer(),
          results: [validation_result()],
          execution_time_ms: integer()
        }

  @doc """
  Executes all validation tests and returns a comprehensive report.

  ## Options
  - `:agent_id` - The agent to test (required)
  - `:profile_id` - The profile to use for execution (default: "req_llm")
  - `:agent_version` - Agent version to test (default: :latest)
  - `:timeout_ms` - Timeout for each test (default: 30_000)

  ## Examples

      iex> AgentWeb.WorkflowValidator.run_validation_tests(agent_id: "test_agent")
      {:ok, %{total_tests: 1, passed: 1, failed: 0, results: [...]}}
  """
  @spec run_validation_tests(keyword()) :: {:ok, validation_report()} | {:error, String.t()}
  def run_validation_tests(opts \\ []) do
    agent_id = Keyword.fetch!(opts, :agent_id)
    profile_id = Keyword.get(opts, :profile_id, "req_llm")
    agent_version = Keyword.get(opts, :agent_version, :latest)
    timeout_ms = Keyword.get(opts, :timeout_ms, 30_000)

    start_time = System.monotonic_time(:millisecond)

    # Ensure we're running in test database isolation
    with :ok <- ensure_test_database(),
         {:ok, profile} <- get_profile(profile_id),
         {:ok, test_results} <- run_all_tests(agent_id, agent_version, profile, timeout_ms) do
      end_time = System.monotonic_time(:millisecond)
      execution_time = end_time - start_time

      passed = Enum.count(test_results, &(&1.status == :passed))
      failed = Enum.count(test_results, &(&1.status == :failed))

      report = %{
        total_tests: length(test_results),
        passed: passed,
        failed: failed,
        results: test_results,
        execution_time_ms: execution_time
      }

      {:ok, report}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Executes the Thanos context retention test scenario.

  This test validates that agents properly retain and use conversation context by:
  1. Sending "My name is Thanos, what is your name?"
  2. Sending "Do you know my name?"
  3. Asserting the response contains "Thanos" and is not a clarification request
  """
  @spec run_thanos_context_test(String.t(), atom() | integer(), term(), integer()) ::
          {:ok, validation_result()} | {:error, String.t()}
  def run_thanos_context_test(agent_id, agent_version, profile, timeout_ms) do
    test_name = "Thanos Context Retention Test"
    start_time = System.monotonic_time(:millisecond)

    try do
      # Create a unique conversation ID for this test
      conversation_id = "test_conversation_#{System.unique_integer([:positive])}"

      # Step 1: Send initial message with name introduction
      first_prompt = "My name is Thanos, what is your name?"

      with {:ok, first_response} <-
             execute_agent_message(
               agent_id,
               agent_version,
               profile,
               first_prompt,
               conversation_id,
               timeout_ms
             ),
           # Step 2: Send follow-up message to test context retention
           second_prompt <- "Do you know my name?",
           {:ok, second_response} <-
             execute_agent_message(
               agent_id,
               agent_version,
               profile,
               second_prompt,
               conversation_id,
               timeout_ms
             ) do
        end_time = System.monotonic_time(:millisecond)
        execution_time = end_time - start_time

        # Validate the second response contains "Thanos" and is not a clarification
        validation_result = validate_thanos_response(second_response)

        result = %{
          test_name: test_name,
          status: if(validation_result.valid?, do: :passed, else: :failed),
          details: validation_result.details,
          execution_time_ms: execution_time,
          responses: [first_response, second_response],
          error: nil
        }

        {:ok, result}
      else
        {:error, reason} ->
          end_time = System.monotonic_time(:millisecond)
          execution_time = end_time - start_time

          result = %{
            test_name: test_name,
            status: :failed,
            details: "Test execution failed: #{inspect(reason)}",
            execution_time_ms: execution_time,
            responses: [],
            error: inspect(reason)
          }

          {:ok, result}
      end
    rescue
      e ->
        end_time = System.monotonic_time(:millisecond)
        execution_time = end_time - start_time

        result = %{
          test_name: test_name,
          status: :failed,
          details: "Test execution error: #{Exception.message(e)}",
          execution_time_ms: execution_time,
          responses: [],
          error: Exception.message(e)
        }

        {:ok, result}
    end
  end

  # Private functions

  defp ensure_test_database do
    # Verify we're running against test database
    config = Application.get_env(:agent_infra, AgentInfra.Repo)
    database = Keyword.get(config, :database, "")

    if String.contains?(database, "test") do
      :ok
    else
      {:error, "Validation tests must run against test database. Current: #{database}"}
    end
  end

  defp get_profile(profile_id) do
    try do
      profile = Profiles.get!(profile_id)
      {:ok, profile}
    rescue
      Ecto.NoResultsError ->
        {:error, "Profile not found: #{profile_id}"}

      e ->
        {:error, "Failed to load profile: #{Exception.message(e)}"}
    end
  end

  defp run_all_tests(agent_id, agent_version, profile, timeout_ms) do
    # Currently only implementing Thanos context retention test
    # Additional tests can be added here in the future
    tests = [
      fn -> run_thanos_context_test(agent_id, agent_version, profile, timeout_ms) end
    ]

    results =
      Enum.map(tests, fn test_fn ->
        case test_fn.() do
          {:ok, result} -> result
          {:error, reason} -> create_error_result("Test execution failed", reason)
        end
      end)

    {:ok, results}
  end

  defp execute_agent_message(
         agent_id,
         agent_version,
         profile,
         message,
         conversation_id,
         timeout_ms
       ) do
    # Prepare execution parameters
    exec_meta = %{
      "conversation_id" => conversation_id,
      "trace_id" => "validation_test_#{System.unique_integer([:positive])}"
    }

    overrides = %{}

    # Convert message to runtime input format
    with {:ok, runtime_input} <-
           InputMapper.to_runtime(%{
             "type" => "chat",
             "messages" => [%{"role" => "user", "content" => message}]
           }) do
      # Execute agent with streaming disabled for testing
      # Note: This uses the agent's configured profiles (execution, assessor, embeddings)
      # rather than forcing a single profile for everything
      case execute_agent_sync(
             profile,
             overrides,
             runtime_input,
             exec_meta,
             agent_id: agent_id,
             agent_version: agent_version,
             timeout_ms: timeout_ms
           ) do
        {:ok, response} -> {:ok, response}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, reason} -> {:error, "Input mapping failed: #{inspect(reason)}"}
    end
  end

  defp execute_agent_sync(profile, overrides, runtime_input, exec_meta, opts) do
    timeout_ms = Keyword.get(opts, :timeout_ms, 30_000)
    agent_id = Keyword.fetch!(opts, :agent_id)
    agent_version = Keyword.fetch!(opts, :agent_version)

    task =
      Task.async(fn ->
        try do
          # Collect streaming response into a single result
          final_response = collect_streaming_response([], timeout_ms)

          AgentExecutor.execute_agent_stream(
            profile,
            overrides,
            runtime_input,
            exec_meta,
            fn chunk ->
              send(self(), {:chunk, chunk})
            end,
            fn _step_id, _status, _metadata ->
              # Workflow progress callback - not needed for validation tests
              :ok
            end,
            agent_id: agent_id,
            agent_version: agent_version
          )

          {:ok, final_response}
        catch
          kind, reason ->
            {:error, {kind, reason}}
        end
      end)

    case Task.yield(task, timeout_ms) || Task.shutdown(task) do
      {:ok, {:ok, response}} ->
        {:ok, response}

      {:ok, {:error, reason}} ->
        {:error, reason}

      nil ->
        {:error, "timeout after #{timeout_ms}ms"}

      {:exit, reason} ->
        {:error, "Agent execution failed: #{inspect(reason)}"}
    end
  end

  defp collect_streaming_response(chunks, timeout_ms) do
    receive do
      {:chunk, %{type: :token, data: %{content: content}}} ->
        collect_streaming_response([content | chunks], timeout_ms)

      {:chunk, %{type: :done}} ->
        chunks |> Enum.reverse() |> Enum.join("")

      {:chunk, %{type: :error, data: %{error: error}}} ->
        throw({:error, error})

      {:chunk, _other} ->
        collect_streaming_response(chunks, timeout_ms)
    after
      timeout_ms ->
        chunks |> Enum.reverse() |> Enum.join("")
    end
  end

  defp validate_thanos_response(response) do
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

  defp create_error_result(test_name, reason) do
    %{
      test_name: test_name,
      status: :failed,
      details: "Test setup failed: #{inspect(reason)}",
      execution_time_ms: 0,
      responses: [],
      error: inspect(reason)
    }
  end
end
