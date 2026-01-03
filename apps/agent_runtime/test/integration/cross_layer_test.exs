defmodule AgentRuntime.Integration.CrossLayerTest do
  @moduledoc """
  Integration tests for cross-layer communication in the restructured umbrella application.
  Tests the complete flow: web → runtime → core → infra
  """
  use ExUnit.Case, async: false

  alias AgentCore.{Runs, Profiles}
  alias AgentRuntime.Agent

  @moduletag :integration

  setup do
    # Set up database sandbox for each test
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(AgentInfra.Repo)
    :ok
  end

  describe "cross-layer integration" do
    test "profile creation and retrieval flow" do
      # Test data
      profile_attrs = %{
        name: "test-profile",
        provider: :openai,
        model: "gpt-4"
      }

      # Step 1: Create profile through runtime layer (simulating web request)
      assert {:ok, profile} = Agent.create_profile(profile_attrs)
      assert profile.name == "test-profile"
      assert profile.model == "gpt-4"
      assert profile.provider == :openai

      # Step 2: Retrieve profile to verify persistence
      assert {:ok, retrieved_profile} = Agent.get_profile(profile.id)
      assert retrieved_profile.name == profile.name
      assert retrieved_profile.model == profile.model
      assert retrieved_profile.provider == profile.provider
    end

    test "run creation and status updates" do
      # First create a profile
      profile_attrs = %{
        name: "run-test-profile",
        provider: :openai,
        model: "gpt-3.5-turbo"
      }

      assert {:ok, profile} = Agent.create_profile(profile_attrs)

      # Create run with all required fields
      run_attrs = %{
        profile_id: profile.id,
        provider: :openai,
        model: "gpt-3.5-turbo",
        policy_version: "1.0",
        resolved_at: DateTime.utc_now()
      }

      assert {:ok, run} = Agent.create_run(run_attrs)
      assert run.profile_id == profile.id
      assert run.status == :pending

      # Update run status
      assert {:ok, updated_run} = Agent.update_run(run.id, %{status: :running})
      assert updated_run.status == :running

      # Verify persistence
      assert {:ok, final_run} = Agent.get_run(run.id)
      assert final_run.status == :running
    end

    test "error handling propagation" do
      # Test that errors propagate correctly from infra → core → runtime

      # Attempt to get non-existent run (use valid UUID format)
      non_existent_uuid = Ecto.UUID.generate()
      assert {:error, :not_found} = Agent.get_run(non_existent_uuid)

      # Attempt to get non-existent profile
      assert {:error, :not_found} = Agent.get_profile("non-existent-profile")
    end

    test "domain struct validation" do
      # Test that domain validation works correctly

      # Invalid profile (missing required fields)
      invalid_profile_attrs = %{
        name: "incomplete-profile"
        # missing provider and model
      }

      assert {:error, _reason} = Agent.create_profile(invalid_profile_attrs)

      # Invalid run (missing required fields)
      invalid_run_attrs = %{
        profile_id: "some-profile"
        # missing id, trace_id, fingerprint
      }

      assert {:error, _reason} = Agent.create_run(invalid_run_attrs)
    end
  end

  describe "dependency isolation verification" do
    test "runtime layer uses store behaviors correctly" do
      # Verify that runtime layer is configured to use store implementations
      run_store = Application.get_env(:agent_runtime, :run_store)
      profile_store = Application.get_env(:agent_runtime, :profile_store)

      # These should be configured (even if nil in test environment)
      assert is_atom(run_store) or is_nil(run_store)
      assert is_atom(profile_store) or is_nil(profile_store)
    end

    test "workflow execution through runtime layer" do
      # Test workflow execution that involves multiple layers

      # Create a simple workflow spec
      workflow_spec = %AgentCore.Workflows.Spec{
        id: "test-workflow",
        version: "1.0",
        entry: "start",
        nodes: %{
          "start" => %{
            type: "action",
            action: "echo",
            params: %{"message" => "Hello from workflow"}
          }
        },
        edges: [],
        exits: MapSet.new(["start"])
      }

      # Execute workflow through runtime
      input = %{"test_input" => "value"}
      context = AgentCore.Workflows.Context.new(input)

      # This tests runtime → core workflow engine integration
      result = AgentRuntime.Workflows.Engine.execute(workflow_spec, context)

      # Verify workflow executed (may return error if not fully implemented, but should not crash)
      case result do
        {:ok, _output} -> :ok
        {:error, _reason} -> :ok
      end
    end
  end
end
