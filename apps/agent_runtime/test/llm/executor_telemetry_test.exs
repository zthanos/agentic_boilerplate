defmodule AgentRuntime.Llm.ExecutorTelemetryTest do
  use ExUnit.Case, async: false

  alias AgentRuntime.Llm.Executor
  alias AgentRuntime.Llm.ProviderRouter
  alias Ecto.Adapters.SQL.Sandbox

  @start_event [:agent_runtime, :llm, :execute, :start]
  @stop_event  [:agent_runtime, :llm, :execute, :stop]
  @error_event [:agent_runtime, :llm, :execute, :error]

  defmodule OkAdapter do
    @behaviour AgentCore.Llm.ProviderAdapter

    @impl true
    def call(_req) do
      {:ok, AgentCore.Llm.ProviderResponse.ok("ok", usage: %{"total_tokens" => 1})}
    end
  end

  defmodule ErrAdapter do
    @behaviour AgentCore.Llm.ProviderAdapter

    @impl true
    def call(_req) do
      {:error, {:boom, :simulated}}
    end
  end

  # Telemetry handler: forwards events into the test process
  def handle_event(event, measurements, metadata, %{test_pid: pid}) do
    send(pid, {:telemetry, event, measurements, metadata})
  end

  setup do
    :ok = Sandbox.checkout(AgentCore.Repo)
    Sandbox.mode(AgentCore.Repo, {:shared, self()})
    handler_id = {__MODULE__, self(), System.unique_integer([:positive])}

    :telemetry.attach_many(
      handler_id,
      [@start_event, @stop_event, @error_event],
      &__MODULE__.handle_event/4,
      %{test_pid: self()}
    )

    prev_router_env = Application.get_env(:agent_runtime, ProviderRouter)

    on_exit(fn ->
      :telemetry.detach(handler_id)

      if is_nil(prev_router_env) do
        Application.delete_env(:agent_runtime, ProviderRouter)
      else
        Application.put_env(:agent_runtime, ProviderRouter, prev_router_env)
      end
    end)

    :ok
  end

  test "emits start + stop on success" do
    Application.put_env(:agent_runtime, ProviderRouter, overrides: %{
      openai_compatible: OkAdapter
    })

    profile = %{
      id: "p1",
      provider: :openai_compatible,
      model: :local,
      generation: %{},
      policy_version: 1
    }


    overrides = %{}

    input = %{
      type: :chat,
      messages: [%{role: :user, content: "hi"}]
    }

    assert {:ok, resp} = Executor.execute(profile, overrides, input)
    assert resp.output_text == "ok"


    assert_received {:telemetry, @start_event, start_meas, start_meta}
    assert is_integer(start_meas.system_time)
    assert start_meta.provider == :openai_compatible
    assert Map.has_key?(start_meta, :resolved_model)

    assert_received {:telemetry, @stop_event, stop_meas, stop_meta}
    assert is_integer(stop_meas.duration_ms)
    assert stop_meta.status == :ok
    assert stop_meta.provider == :openai_compatible
    assert Map.has_key?(stop_meta, :resolved_model)
    assert stop_meta.usage == %{"total_tokens" => 1}

    refute_received {:telemetry, @error_event, _m, _md}
  end

  test "emits start + error on failure" do
    Application.put_env(:agent_runtime, ProviderRouter, overrides: %{
      openai_compatible: ErrAdapter
    })

    profile = %{
      id: "p1",
      provider: :openai_compatible,
      model: :local,
      generation: %{},
      policy_version: 1
    }


    overrides = %{}

    input = %{
      type: :chat,
      messages: [%{role: :user, content: "hi"}]
    }

    assert {:error, {:boom, :simulated}} = Executor.execute(profile, overrides, input)

    assert_received {:telemetry, @start_event, _start_meas, start_meta}
    assert start_meta.provider == :openai_compatible
    assert Map.has_key?(start_meta, :resolved_model)

    assert_received {:telemetry, @error_event, err_meas, err_meta}
    assert is_integer(err_meas.duration_ms)
    assert err_meta.status == :error
    assert err_meta.provider == :openai_compatible
    assert err_meta.reason == {:boom, :simulated}
    assert Map.has_key?(err_meta, :resolved_model)

    refute_received {:telemetry, @stop_event, _m, _md}
  end
end
