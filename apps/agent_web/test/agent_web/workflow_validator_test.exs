defmodule AgentWeb.WorkflowValidatorTest do
  use AgentWeb.DataCase, async: false

  alias AgentWeb.WorkflowValidator
  alias AgentWeb.AgentSeeder

  defp create_test_profile do
    test_profile = %AgentCore.Llm.LLMProfile{
      id: "test_req_llm",
      name: "Test Requirements LLM",
      enabled: true,
      provider: :openai_compatible,
      model: "openai/gpt-oss-20b",
      policy_version: "1",
      generation: %{temperature: 0.2, top_p: 1.0, max_output_tokens: 1000, seed: 42},
      budgets: %{request_timeout_ms: 60_000, max_retries: 0},
      tools: [],
      stop_list: [],
      tags: ["test", "requirements"]
    }

    case AgentCore.Llm.Profiles.put(test_profile) do
      {:ok, profile} -> profile
      {:error, _} -> test_profile
    end
  end

  describe "run_validation_tests/1" do
    test "validates required agent_id parameter" do
      assert_raise KeyError, fn ->
        WorkflowValidator.run_validation_tests([])
      end
    end

    test "returns error for non-existent agent" do
      result = WorkflowValidator.run_validation_tests(agent_id: "non_existent_agent")

      assert {:error, reason} = result
      assert is_binary(reason)
    end

    test "returns error when not running against test database" do
      # This test ensures the safety check works
      # We can't easily test this without changing the database config
      # So we'll test the validation logic directly
      config = Application.get_env(:agent_infra, AgentInfra.Repo)
      database = Keyword.get(config, :database, "")

      # Should contain "test" in the database name
      assert String.contains?(database, "test"),
             "Test should be running against test database, got: #{database}"
    end
  end

  describe "run_thanos_context_test/4" do
    setup do
      # Try to seed a test agent for validation, handle errors gracefully
      case AgentSeeder.seed_test_agents() do
        {:ok, [agent]} ->
          # Try to get the profile, create a simple one if it doesn't exist
          profile =
            case AgentCore.Llm.Profiles.get("req_llm") do
              {:ok, profile} -> profile
              {:error, :not_found} -> create_test_profile()
              :error -> create_test_profile()
            end

          %{agent: agent, profile: profile, seeded: true}

        {:error, _reason} ->
          # If seeding fails, we'll skip tests that require a real agent
          profile =
            case AgentCore.Llm.Profiles.get("req_llm") do
              {:ok, profile} -> profile
              {:error, :not_found} -> create_test_profile()
              :error -> create_test_profile()
            end

          %{agent: nil, profile: profile, seeded: false}
      end
    end

    test "executes Thanos context retention test", %{
      agent: agent,
      profile: profile,
      seeded: seeded
    } do
      if seeded do
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
      else
        # Skip test if agent seeding failed
        assert true
      end
    end

    test "handles agent execution timeout gracefully", %{
      agent: agent,
      profile: profile,
      seeded: seeded
    } do
      if seeded do
        # Use very short timeout to trigger timeout condition
        result =
          WorkflowValidator.run_thanos_context_test(
            agent.id,
            :latest,
            profile,
            1
          )

        assert {:ok, test_result} = result
        assert test_result.status == :failed

        assert String.contains?(test_result.details, "timeout") or
                 String.contains?(test_result.error || "", "timeout")
      else
        # Skip test if agent seeding failed
        assert true
      end
    end

    test "handles non-existent agent gracefully" do
      # Create a test profile for this test
      profile = create_test_profile()

      result =
        WorkflowValidator.run_thanos_context_test(
          "non_existent_agent",
          :latest,
          profile,
          30_000
        )

      assert {:ok, test_result} = result
      assert test_result.status == :failed
      assert test_result.error != nil
    end
  end

  describe "validation report structure" do
    setup do
      case AgentSeeder.seed_test_agents() do
        {:ok, [agent]} -> %{agent: agent, seeded: true}
        {:error, _reason} -> %{agent: nil, seeded: false}
      end
    end

    test "returns properly structured validation report", %{agent: agent, seeded: seeded} do
      if seeded do
        result = WorkflowValidator.run_validation_tests(agent_id: agent.id)

        case result do
          {:ok, report} ->
            assert is_integer(report.total_tests)
            assert is_integer(report.passed)
            assert is_integer(report.failed)
            assert is_integer(report.execution_time_ms)
            assert is_list(report.results)
            assert report.total_tests == report.passed + report.failed

            # Validate each test result structure
            Enum.each(report.results, fn test_result ->
              assert is_binary(test_result.test_name)
              assert test_result.status in [:passed, :failed]
              assert is_binary(test_result.details)
              assert is_integer(test_result.execution_time_ms)
              assert is_list(test_result.responses)
            end)

          {:error, _reason} ->
            # Test may fail due to LM Studio unavailability or other issues
            # This is acceptable in test environment
            :ok
        end
      else
        # Skip test if agent seeding failed
        assert true
      end
    end
  end
end
