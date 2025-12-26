defmodule AgentCore.Llm.RunStoreEctoTest do
  use ExUnit.Case, async: false

  alias AgentCore.Llm.{RunSnapshot, Runs}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(AgentCore.Repo)
    :ok
  end

  test "put/1 persists snapshot and get_by_fingerprint/1 loads it" do
    fp = "fp_test_" <> Integer.to_string(System.unique_integer([:positive]))

    snap = %RunSnapshot{
      fingerprint: fp,
      profile_id: "p_default",
      profile_name: "Default GPT Profile",
      provider: :openai,
      model: "gpt-4.1-mini",
      policy_version: "merge_policy.v1",
      resolved_at: DateTime.utc_now(),
      overrides: %{"generation" => %{"temperature" => 0.7}},
      invocation_config: %{
        "provider" => "openai",
        "model" => "gpt-4.1-mini",
        "generation" => %{"temperature" => 0.7},
        "fingerprint" => fp
      }
    }

    assert {:ok, ^fp} = Runs.put(snap)
    assert {:ok, loaded} = Runs.get_by_fingerprint(fp)

    assert loaded.fingerprint == fp
    assert to_string(loaded.profile_id) == "p_default"
    assert loaded.provider in ["openai", :openai]
    assert loaded.model in ["gpt-4.1-mini", :"gpt-4.1-mini"]

    # JSON maps are persisted/retrieved
    assert loaded.overrides["generation"]["temperature"] == 0.7
    assert loaded.invocation_config["generation"]["temperature"] == 0.7
  end

  test "put/1 is idempotent for same fingerprint (dedup)" do
    fp = "fp_test_" <> Integer.to_string(System.unique_integer([:positive]))

    base = %RunSnapshot{
      fingerprint: fp,
      profile_id: "p_default",
      profile_name: "Default GPT Profile",
      provider: :openai,
      model: "gpt-4.1-mini",
      policy_version: "merge_policy.v1",
      resolved_at: DateTime.utc_now(),
      overrides: %{},
      invocation_config: %{"fingerprint" => fp}
    }

    assert {:ok, ^fp} = Runs.put(base)

    # second insert with same fingerprint should still succeed (adapter returns ok)
    assert {:ok, ^fp} = Runs.put(%{base | profile_name: "Changed Name"})
    assert {:ok, loaded} = Runs.get_by_fingerprint(fp)

    # Depending on on_conflict policy, record might be the first one.
    # We assert only that the key exists and is retrievable.
    assert loaded.fingerprint == fp
  end
end
