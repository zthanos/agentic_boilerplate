defmodule AgentCore.WorkflowEngine.ContextTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias AgentCore.WorkflowEngine.Context

  describe "Context creation" do
    test "creates new context with empty maps" do
      ctx = Context.new()

      assert ctx.decisions == %{}
      assert ctx.artifacts == %{}
      assert ctx.debug == %{}
      assert ctx.meta == %{}
      assert ctx.events == []
    end

    test "creates new context with initial metadata" do
      initial_meta = %{run_id: "123", trace_id: "abc"}
      ctx = Context.new(initial_meta)

      assert ctx.meta == initial_meta
      assert ctx.decisions == %{}
      assert ctx.artifacts == %{}
      assert ctx.debug == %{}
      assert ctx.events == []
    end
  end

  describe "decision management" do
    test "puts and gets decisions" do
      ctx =
        Context.new()
        |> Context.put_decision(:needs_history, true)
        |> Context.put_decision(:process_type, :async)

      assert Context.get_decision(ctx, :needs_history) == true
      assert Context.get_decision(ctx, :process_type) == :async
      assert Context.get_decision(ctx, :missing) == nil
    end

    test "overwrites existing decisions" do
      ctx =
        Context.new()
        |> Context.put_decision(:flag, false)
        |> Context.put_decision(:flag, true)

      assert Context.get_decision(ctx, :flag) == true
    end
  end

  describe "artifact management" do
    test "puts and gets artifacts" do
      data = %{processed: true, count: 5}

      ctx =
        Context.new()
        |> Context.put_artifact(:result, data)
        |> Context.put_artifact(:metadata, %{version: 1})

      assert Context.get_artifact(ctx, :result) == data
      assert Context.get_artifact(ctx, :metadata) == %{version: 1}
      assert Context.get_artifact(ctx, :missing) == nil
    end

    test "handles complex artifact data" do
      complex_data = %{
        items: [1, 2, 3],
        nested: %{deep: %{value: "test"}},
        list_of_maps: [%{id: 1}, %{id: 2}]
      }

      ctx =
        Context.new()
        |> Context.put_artifact(:complex, complex_data)

      assert Context.get_artifact(ctx, :complex) == complex_data
    end
  end

  describe "debug information" do
    test "puts and gets debug info" do
      ctx =
        Context.new()
        |> Context.put_debug(:step_duration, 150)
        |> Context.put_debug(:memory_usage, 1024)

      assert ctx.debug[:step_duration] == 150
      assert ctx.debug[:memory_usage] == 1024
    end
  end

  describe "event management" do
    test "adds events to the stream" do
      event1 = %{type: :step_started, node: :process, timestamp: 123}
      event2 = %{type: :step_completed, node: :process, timestamp: 456}

      ctx =
        Context.new()
        |> Context.add_event(event1)
        |> Context.add_event(event2)

      assert length(ctx.events) == 2
      # Events are prepended, so most recent is first
      assert hd(ctx.events) == event2
      assert ctx.events == [event2, event1]
    end

    test "handles empty event stream" do
      ctx = Context.new()
      assert ctx.events == []
    end
  end

  describe "immutability" do
    test "context operations return new context" do
      original_ctx = Context.new()
      new_ctx = Context.put_decision(original_ctx, :test, true)

      assert original_ctx.decisions == %{}
      assert new_ctx.decisions == %{test: true}
      refute original_ctx == new_ctx
    end

    test "nested updates work correctly" do
      ctx =
        Context.new()
        |> Context.put_decision(:step1, :complete)
        |> Context.put_artifact(:data, %{value: 1})
        |> Context.put_debug(:timing, 100)

      assert ctx.decisions[:step1] == :complete
      assert ctx.artifacts[:data] == %{value: 1}
      assert ctx.debug[:timing] == 100
    end
  end

  describe "data separation" do
    test "different maps maintain separation" do
      ctx =
        Context.new()
        |> Context.put_decision(:key, :decision_value)
        |> Context.put_artifact(:key, :artifact_value)
        |> Context.put_debug(:key, :debug_value)

      assert Context.get_decision(ctx, :key) == :decision_value
      assert Context.get_artifact(ctx, :key) == :artifact_value
      assert ctx.debug[:key] == :debug_value
    end
  end

  # Property-based tests will be added in separate tasks
end
