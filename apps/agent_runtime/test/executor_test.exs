defmodule AgentRuntime.Llm.ExecutorTest do
  use ExUnit.Case, async: false

  # import Ecto.Query

  alias AgentRuntime.Llm.Executor
  # alias AgentCore.Llm.RunRecord
  alias AgentCore.Repo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    :ok
  end

  # test "execute persists run and completes lifecycle" do
  #   profile = %{
  #     id: "p1",
  #     provider: :fake,
  #     model: :gpt_test,
  #     policy_version: "1"
  #   }

  #   overrides = %{}
  #   input = %{type: :completion, prompt: "hello"}

  #   assert {:ok, resp} = Executor.execute(profile, overrides, input)
  #   assert resp.output_text == "FAKE: hello"

  #   rec =
  #     Repo.one!(
  #       from r in RunRecord,
  #         order_by: [desc: r.inserted_at],
  #         limit: 1
  #     )

  #   assert rec.status == "finished"
  #   assert rec.started_at != nil
  #   assert rec.finished_at != nil
  #   assert rec.latency_ms != nil
  # end

  test "execute returns response" do
    profile = %{id: "p1", provider: :fake, model: :gpt_test, policy_version: "1"}
    overrides = %{}
    input = %{type: :completion, prompt: "hello"}

    assert {:ok, resp} = Executor.execute(profile, overrides, input)
    assert resp.output_text == "FAKE: hello"
  end

  test "router ignores invalid overrides and falls back to default" do
    prev = Application.get_env(:agent_runtime, AgentRuntime.Llm.ProviderRouter, [])

    Application.put_env(:agent_runtime, AgentRuntime.Llm.ProviderRouter, overrides: %{fake: nil})

    assert {:ok, mod} = AgentRuntime.Llm.ProviderRouter.route(:fake)
    assert mod == AgentCore.Llm.Providers.FakeProvider

    on_exit(fn ->
      Application.put_env(:agent_runtime, AgentRuntime.Llm.ProviderRouter, prev)
    end)
  end

end
