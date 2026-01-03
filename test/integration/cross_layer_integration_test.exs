defmodule Integration.CrossLayerIntegrationTest do
  @moduledoc """
  Integration tests for cross-layer communication in the restructured umbrella application.
  Tests the complete flow: web → runtime → core → infra
  """
  use ExUnit.Case, async: false

  alias AgentCore.{Runs, Profiles}
  alias AgentCore.Stores.{RunStore, ProfileStore}
  alias AgentRuntime.Agent
  alias AgentInfra.Repo

  @moduletag :integration

  setup do
    # Ensure clean database state for each test
    Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    # Configure store implementations for testing
    Application.put_env(:agent_runtime, :run_store, AgentInfra.StoreEcto.RunStore)
    Application.put_env(:agent_runtime, :profile_store, AgentInfra.StoreEcto.ProfileStore)

    :ok
  end

  describe "web → runtime → core → infra communication flow" do
    test "complete run creation and execution flow" do
      # Test data
      profile_attrs = %{
        name: "test-profile",
        model: "gpt-4",
        temperature: 0.7,
        max_tokens: 1000
      }

      run_attrs = %{
        profile_id: "test-profile-id",
        status: :pending,
        metadata: %{"test" => true}
      }

      # Step 1: Create profile through runtime layer (simulating web request)
      assert {:ok, profile} = Agent.create_profile(profile_attrs)
      assert profile.name == "test-profile"
      assert profile.model == "gpt-4"

      # Step 2: Verify profile was persisted through infra layer
      assert {:ok, stored_profile} = ProfileStore.get(profile.id)
      assert stored_profile.name == profile.name
      assert stored_profile.model == profile.model

      # Step 3: Create run through runtime layer
      run_attrs = Map.put(run_attrs, :profile_id, profile.id)
      assert {:ok, run} = Agent.create_run(run_attrs)
      assert run.profile_id == profile.id
      assert run.status == :pending

      # Step 4: Verify run was persisted through infra layer
      assert {:ok, stored_run} = RunStore.get(run.id)
      assert stored_run.profile_id == run.profile_id
      assert stored_run.status == run.status

      # Step 5: Update run status through runtime layer
      assert {:ok, updated_run} = Agent.update_run(run.id, %{status: :running})
      assert updated_run.status == :running

      # Step 6: Verify update was persisted
      assert {:ok, final_run} = RunStore.get(run.id)
      assert final_run.status == :running
    end

    test "error handling propagation across layers" do
      # Test that errors propagate correctly from infra → core → runtime

      # Attempt to get non-existent run
      assert {:error, :not_found} = Agent.get_run("non-existent-id")

      # Attempt to create run with invalid profile_id
      invalid_run_attrs = %{
        profile_id: "non-existent-profile",
        status: :pending
      }

      # This should fail at the infra layer and propagate up
      assert {:error, _reason} = Agent.create_run(invalid_run_attrs)
    end

    test "store behavior implementations work correctly with real database" do
      # Test that store behaviors correctly convert between domain structs and DB schemas

      # Create a profile directly through store behavior
      profile = %Profiles{
        id: "test-profile-123",
        name: "direct-store-test",
        provider: :openai,
        model: "gpt-3.5-turbo"
      }

      # Store through behavior interface
      store_impl = Application.get_env(:agent_runtime, :profile_store)
      assert {:ok, stored_profile} = store_impl.create(profile)

      # Verify it's a domain struct, not a schema
      assert %Profiles{} = stored_profile
      assert stored_profile.name == "direct-store-test"

      # Retrieve and verify conversion
      assert {:ok, retrieved_profile} = store_impl.get(stored_profile.id)
      assert %Profiles{} = retrieved_profile
      assert retrieved_profile.name == stored_profile.name
      assert retrieved_profile.model == stored_profile.model
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
        exits: ["start"]
      }

      # Execute workflow through runtime
      input = %{"test_input" => "value"}

      # This tests runtime → core workflow engine integration
      result = AgentRuntime.Workflows.Engine.execute(workflow_spec, input)

      # Verify workflow executed successfully
      assert {:ok, _output} = result
    end
  end

  describe "dependency isolation verification" do
    test "agent_web has no direct infra dependencies" do
      # Verify that agent_web modules don't directly import agent_infra
      web_modules = get_modules_in_app(:agent_web)

      for module <- web_modules do
        module_source = get_module_source(module)
        refute String.contains?(module_source, "AgentInfra."),
               "#{module} should not directly import AgentInfra modules"
        refute String.contains?(module_source, "alias AgentInfra"),
               "#{module} should not alias AgentInfra modules"
      end
    end

    test "agent_runtime has no direct infra dependencies except for store implementations" do
      # Verify that agent_runtime modules don't directly use Ecto or Repo
      runtime_modules = get_modules_in_app(:agent_runtime)

      for module <- runtime_modules do
        module_source = get_module_source(module)
        refute String.contains?(module_source, "AgentInfra.Repo"),
               "#{module} should not directly use AgentInfra.Repo"
        refute String.contains?(module_source, "Ecto.Query"),
               "#{module} should not directly use Ecto.Query"
      end
    end

    test "agent_core has no infrastructure dependencies" do
      # Verify that agent_core has no Ecto, Repo, or HTTP client dependencies
      core_modules = get_modules_in_app(:agent_core)

      for module <- core_modules do
        module_source = get_module_source(module)
        refute String.contains?(module_source, "use Ecto.Schema"),
               "#{module} should not use Ecto.Schema"
        refute String.contains?(module_source, "Ecto.Repo"),
               "#{module} should not use Ecto.Repo"
        refute String.contains?(module_source, "Req."),
               "#{module} should not use HTTP clients directly"
      end
    end
  end

  # Helper functions
  defp get_modules_in_app(app_name) do
    app_path = Path.join(["apps", Atom.to_string(app_name), "lib"])

    if File.exists?(app_path) do
      app_path
      |> Path.join("**/*.ex")
      |> Path.wildcard()
      |> Enum.map(&extract_module_name/1)
      |> Enum.reject(&is_nil/1)
    else
      []
    end
  end

  defp extract_module_name(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        case Regex.run(~r/defmodule\s+([A-Za-z0-9_.]+)/, content) do
          [_, module_name] -> String.to_atom(module_name)
          _ -> nil
        end
      _ -> nil
    end
  end

  defp get_module_source(module) when is_atom(module) do
    case :code.which(module) do
      :non_existing -> ""
      beam_path when is_list(beam_path) ->
        # Try to find the source file
        source_path = beam_path
        |> to_string()
        |> String.replace(~r/\.beam$/, ".ex")
        |> String.replace("_build/test/lib/", "apps/")
        |> String.replace(~r/ebin\/Elixir\.[^\/]+\.ex$/, "lib/")

        # Reconstruct likely source path
        parts = String.split(to_string(module), ".")
        app_name = parts |> hd() |> String.downcase()

        possible_paths = [
          Path.join(["apps", app_name, "lib", Enum.join(Enum.map(parts, &Macro.underscore/1), "/") <> ".ex"]),
          Path.join(["apps", app_name, "lib", String.downcase(app_name) <> ".ex"])
        ]

        Enum.find_value(possible_paths, "", fn path ->
          if File.exists?(path) do
            File.read!(path)
          end
        end)
    end
  end
end
