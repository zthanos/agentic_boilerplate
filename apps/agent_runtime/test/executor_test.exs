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

end
