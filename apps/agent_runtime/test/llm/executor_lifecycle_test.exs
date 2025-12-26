defmodule AgentRuntime.Llm.ExecutorLifecycleTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias AgentRuntime.Llm.Executor
  alias AgentCore.Repo
  alias AgentCore.Llm.RunRecord

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    :ok
  end

  test "execute persists run and marks it finished on success" do
    profile = %{
      id: "p_lifecycle_success",
      provider: :fake,
      model: "test-model",
      policy_version: "1"
    }

    overrides = %{}
    input = %{type: :completion, prompt: "hello"}

    assert {:ok, resp} = Executor.execute(profile, overrides, input)
    assert is_binary(resp.output_text)
    assert byte_size(resp.output_text) > 0

    rec =
      Repo.one!(
        from r in RunRecord,
          where: r.profile_id == ^profile.id,
          order_by: [desc: r.inserted_at],
          limit: 1
      )

    assert rec.status == "finished"
    assert rec.started_at != nil
    assert rec.finished_at != nil
    assert is_integer(rec.latency_ms) and rec.latency_ms >= 0

    # Optional (only if you store these fields on RunRecord)
    # assert rec.provider in ["fake", "openai_compatible"]
    # assert rec.model == "test-model"
  end

  test "execute persists run and marks it failed when provider is unsupported" do
    profile = %{
      id: "p_lifecycle_failure",
      provider: :definitely_not_supported,
      model: "test-model",
      policy_version: "1"
    }

    overrides = %{}
    input = %{type: :completion, prompt: "hello"}

    assert {:error, _reason} = Executor.execute(profile, overrides, input)

    rec =
      Repo.one!(
        from r in RunRecord,
          where: r.profile_id == ^profile.id,
          order_by: [desc: r.inserted_at],
          limit: 1
      )

    assert rec.status == "failed"
    assert rec.started_at != nil
    assert rec.finished_at != nil
    assert is_integer(rec.latency_ms) and rec.latency_ms >= 0

    # If your RunRecord has an :error field (it does in your Ecto store update),
    # this is a useful assertion:
    if Map.has_key?(rec, :error) do
      assert rec.error != nil
    end
  end
end
