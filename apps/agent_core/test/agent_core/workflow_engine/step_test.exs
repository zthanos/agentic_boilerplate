defmodule AgentCore.WorkflowEngine.StepTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias AgentCore.WorkflowEngine.Step

  # Test step implementation for testing
  defmodule TestStep do
    @behaviour Step

    @impl true
    def id, do: :test_step

    @impl true
    def run(ctx, input, opts) do
      case Map.get(opts, :behavior, :ok) do
        :ok ->
          updated_ctx = put_in(ctx.artifacts[:test_result], input)
          {:ok, updated_ctx, %{processed: true}}

        :skip ->
          {:skip, ctx, %{reason: :skipped}}

        :error ->
          {:error, ctx, %{error: :test_error}}
      end
    end
  end

  describe "Step behavior" do
    test "defines required callbacks" do
      assert function_exported?(Step, :behaviour_info, 1)
      callbacks = Step.behaviour_info(:callbacks)

      assert {:id, 0} in callbacks
      assert {:run, 3} in callbacks
    end

    test "test step implements behavior correctly" do
      assert TestStep.id() == :test_step

      ctx = %{artifacts: %{}, decisions: %{}, debug: %{}, meta: %{}, events: []}
      input = %{data: "test"}
      opts = %{}

      assert {:ok, updated_ctx, output} = TestStep.run(ctx, input, opts)
      assert updated_ctx.artifacts[:test_result] == input
      assert output == %{processed: true}
    end

    test "test step can skip" do
      ctx = %{artifacts: %{}, decisions: %{}, debug: %{}, meta: %{}, events: []}
      input = %{data: "test"}
      opts = %{behavior: :skip}

      assert {:skip, ^ctx, %{reason: :skipped}} = TestStep.run(ctx, input, opts)
    end

    test "test step can error" do
      ctx = %{artifacts: %{}, decisions: %{}, debug: %{}, meta: %{}, events: []}
      input = %{data: "test"}
      opts = %{behavior: :error}

      assert {:error, ^ctx, %{error: :test_error}} = TestStep.run(ctx, input, opts)
    end
  end

  # Property-based tests will be added in separate tasks
end
