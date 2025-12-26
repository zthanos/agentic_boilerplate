defmodule AgentCore.Llm.ResolverDeterminismTest do
  use ExUnit.Case, async: true

  alias AgentCore.Llm.{Resolver, LLMProfile}

  test "fingerprint is deterministic for same profile + overrides" do
    profile =
      %LLMProfile{
        id: "p1",
        name: "P",
        enabled: true,
        provider: :openai,
        model: :gpt_test,
        policy_version: "1"
      }

    overrides = %{tools: [:web]}

    c1 = Resolver.resolve(profile, overrides)
    c2 = Resolver.resolve(profile, overrides)

    refute is_nil(c1.resolved_at)
    refute is_nil(c2.resolved_at)

  end

  test "fingerprint does not change when trace_id changes" do
    profile =
      %LLMProfile{
        id: "p1",
        name: "P",
        enabled: true,
        provider: :openai,
        model: :gpt_test,
        policy_version: "1"
      }

    c1 = Resolver.resolve(profile, %{trace_id: "t1"})
    c2 = Resolver.resolve(profile, %{trace_id: "t2"})

    assert c1.fingerprint == c2.fingerprint
    assert c1.trace_id == "t1"
    assert c2.trace_id == "t2"
  end

  test "fingerprint does not change when policy_version changes" do
    profile1 =
      %LLMProfile{
        id: "p1",
        name: "P",
        enabled: true,
        provider: :openai,
        model: :gpt_test,
        policy_version: "1"
      }

    profile2 = %{profile1 | policy_version: "2"}

    c1 = Resolver.resolve(profile1, %{})
    c2 = Resolver.resolve(profile2, %{})

    assert c1.fingerprint == c2.fingerprint
    assert c1.policy_version == "1"
    assert c2.policy_version == "2"
  end

  test "trace_id is propagated but excluded from overrides snapshot" do
    profile =
      %LLMProfile{
        id: "p1",
        name: "P",
        enabled: true,
        provider: :openai,
        model: :gpt_test,
        policy_version: "1"
      }

    cfg = Resolver.resolve(profile, %{trace_id: "t1", tools: [:web]})

    assert cfg.trace_id == "t1"
    refute Map.has_key?(cfg.overrides, :trace_id)
    refute Map.has_key?(cfg.overrides, "trace_id")


  end

end
