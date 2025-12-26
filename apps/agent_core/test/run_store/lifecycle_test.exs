defmodule AgentCore.RunStore.LifecycleTest do
  use ExUnit.Case, async: false

  alias AgentCore.Llm.RunStore.Ecto, as: RunStore
  alias AgentCore.Llm.{RunSnapshot, RunRecord}
  alias AgentCore.Repo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    :ok
  end

  test "mark_started sets status and started_at" do
    snap = build_snapshot("fp-1")

    assert {:ok, "fp-1"} = RunStore.put(snap)
    assert {:ok, "fp-1"} = RunStore.mark_started("fp-1")

    rec = fetch_run_record!("fp-1")
    assert rec.status == "started"
    assert rec.started_at != nil
  end

  test "mark_finished sets status finished, finished_at and usage" do
    snap = build_snapshot("fp-2")

    assert {:ok, "fp-2"} = RunStore.put(snap)
    assert {:ok, "fp-2"} = RunStore.mark_started("fp-2")
    assert {:ok, "fp-2"} = RunStore.mark_finished("fp-2", %{usage: %{total_tokens: 123}})

    rec = fetch_run_record!("fp-2")
    assert rec.status == "finished"
    assert rec.finished_at != nil

    # Stored map keys may be strings or atoms depending on adapter/encoding.
    assert rec.usage["total_tokens"] == 123 or rec.usage[:total_tokens] == 123
  end

  test "mark_failed sets status failed and stores error" do
    snap = build_snapshot("fp-3")

    assert {:ok, "fp-3"} = RunStore.put(snap)
    assert {:ok, "fp-3"} = RunStore.mark_failed("fp-3", :boom)

    rec = fetch_run_record!("fp-3")
    assert rec.status == "failed"
    assert rec.finished_at != nil
    assert rec.error != nil
  end

  # -----------------------
  # Helpers
  # -----------------------

  defp build_snapshot(fingerprint) do
    %RunSnapshot{
      fingerprint: fingerprint,
      profile_id: "p1",
      profile_name: "Profile",
      provider: :openai,
      model: :gpt_test,
      policy_version: "1",
      resolved_at: DateTime.utc_now(),
      overrides: %{tools: [:web]},
      invocation_config: %{tools: ["web.search"], temperature: 0.2}
    }
  end

  defp fetch_run_record!(fingerprint) do
    Repo.get!(RunRecord, fingerprint)
  end
end
