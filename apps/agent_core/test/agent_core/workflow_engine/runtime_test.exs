defmodule AgentCore.WorkflowEngine.RuntimeTest do
  use ExUnit.Case, async: true

  alias AgentCore.WorkflowEngine.{Runtime, Spec, Context, WorkflowResult}

  # Test step modules
  defmodule TestStartStep do
    @behaviour AgentCore.WorkflowEngine.Step

    def id, do: :test_start

    def run(ctx, _input, _opts) do
      updated_ctx = Context.put_decision(ctx, :started, true)
      {:ok, updated_ctx, %{message: "started"}}
    end
  end

  defmodule TestProcessStep do
    @behaviour AgentCore.WorkflowEngine.Step

    def id, do: :test_process

    def run(ctx, input, _opts) do
      data = Map.get(input, :data, "default")
      updated_ctx = Context.put_artifact(ctx, :processed_data, "processed_#{data}")
      {:ok, updated_ctx, %{processed: true}}
    end
  end

  defmodule TestDoneStep do
    @behaviour AgentCore.WorkflowEngine.Step

    def id, do: :test_done

    def run(ctx, _input, _opts) do
      final_output = %{
        result: Context.get_artifact(ctx, :processed_data),
        started: Context.get_decision(ctx, :started)
      }

      updated_ctx = Context.put_artifact(ctx, :final_output, final_output)
      {:ok, updated_ctx, %{completed: true}}
    end
  end

  defmodule TestErrorStep do
    @behaviour AgentCore.WorkflowEngine.Step

    def id, do: :test_error

    def run(ctx, _input, _opts) do
      {:error, ctx, %{reason: :intentional_error}}
    end
  end

  describe "execute/3" do
    test "executes a simple linear workflow successfully" do
      spec = %Spec{
        id: :test_workflow,
        version: 1,
        entry: :start,
        exits: MapSet.new([:done]),
        nodes: %{
          start: %{step: TestStartStep, opts: %{}},
          process: %{step: TestProcessStep, opts: %{}},
          done: %{step: TestDoneStep, opts: %{}}
        },
        edges: [
          %{from: :start, to: :process, when: {:decision, :started, true}},
          %{from: :process, to: :done, when: {:always}}
        ]
      }

      input = %{data: "test_input"}

      assert {:ok, result} = Runtime.execute(spec, input)
      assert result.status == :ok
      assert result.visited_nodes == [:start, :process, :done]

      assert result.final_output == %{
               result: "processed_test_input",
               started: true
             }

      assert length(result.trace) == 3

      # Check trace entries have required fields
      Enum.each(result.trace, fn trace_entry ->
        assert Map.has_key?(trace_entry, :node_id)
        assert Map.has_key?(trace_entry, :step_module)
        assert Map.has_key?(trace_entry, :status)
        assert Map.has_key?(trace_entry, :duration_ms)
        assert Map.has_key?(trace_entry, :input_keys)
        assert Map.has_key?(trace_entry, :output_keys)
      end)
    end

    test "handles workflow with step error" do
      spec = %Spec{
        id: :error_workflow,
        version: 1,
        entry: :start,
        exits: MapSet.new([:done]),
        nodes: %{
          start: %{step: TestStartStep, opts: %{}},
          error: %{step: TestErrorStep, opts: %{}},
          done: %{step: TestDoneStep, opts: %{}}
        },
        edges: [
          %{from: :start, to: :error, when: {:decision, :started, true}},
          %{from: :error, to: :done, when: {:always}}
        ]
      }

      input = %{data: "test"}

      assert {:error, result} = Runtime.execute(spec, input)
      assert result.status == :failed
      assert result.visited_nodes == [:start, :error]
      assert result.error == %{reason: :intentional_error}
      assert length(result.trace) == 2
    end

    test "handles unresolved transition" do
      spec = %Spec{
        id: :unresolved_workflow,
        version: 1,
        entry: :start,
        exits: MapSet.new([:done]),
        nodes: %{
          start: %{step: TestStartStep, opts: %{}},
          done: %{step: TestDoneStep, opts: %{}}
        },
        edges: [
          # No edge matches since we set :started to true but look for false
          %{from: :start, to: :done, when: {:decision, :started, false}}
        ]
      }

      input = %{data: "test"}

      assert {:error, result} = Runtime.execute(spec, input)
      assert result.status == :failed
      assert result.visited_nodes == [:start]
      assert %{type: :unresolved_transition} = result.error
    end

    test "handles invalid workflow specification" do
      invalid_spec = %Spec{
        id: :invalid,
        version: 1,
        entry: :nonexistent,
        exits: MapSet.new([:done]),
        nodes: %{},
        edges: []
      }

      input = %{data: "test"}

      assert {:error, result} = Runtime.execute(invalid_spec, input)
      assert result.status == :error
      assert %{type: :validation_error} = result.error
    end

    test "evaluates different predicate types correctly" do
      defmodule TestConditionalStep do
        @behaviour AgentCore.WorkflowEngine.Step

        def id, do: :test_conditional

        def run(ctx, _input, _opts) do
          updated_ctx =
            ctx
            |> Context.put_decision(:condition_met, true)
            |> Context.put_artifact(:test_artifact, "present")

          {:ok, updated_ctx, %{conditional: true}}
        end
      end

      spec = %Spec{
        id: :predicate_test,
        version: 1,
        entry: :start,
        exits: MapSet.new([:done]),
        nodes: %{
          start: %{step: TestConditionalStep, opts: %{}},
          done: %{step: TestDoneStep, opts: %{}}
        },
        edges: [
          %{from: :start, to: :done, when: {:artifact_present, :test_artifact}}
        ]
      }

      input = %{data: "test"}

      assert {:ok, result} = Runtime.execute(spec, input)
      assert result.status == :ok
      assert result.visited_nodes == [:start, :done]
    end

    test "evaluates custom predicate functions" do
      custom_predicate = fn ctx ->
        Context.get_decision(ctx, :started) == true
      end

      spec = %Spec{
        id: :custom_predicate_test,
        version: 1,
        entry: :start,
        exits: MapSet.new([:done]),
        nodes: %{
          start: %{step: TestStartStep, opts: %{}},
          done: %{step: TestDoneStep, opts: %{}}
        },
        edges: [
          %{from: :start, to: :done, when: {:custom, custom_predicate}}
        ]
      }

      input = %{data: "test"}

      assert {:ok, result} = Runtime.execute(spec, input)
      assert result.status == :ok
      assert result.visited_nodes == [:start, :done]
    end
  end
end
