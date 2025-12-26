defmodule AgentCore.Llm.ReqLlmProfileTest do
  use ExUnit.Case, async: false

  alias AgentCore.Repo
  alias AgentCore.Llm.{LLMProfile, Profiles, Resolver}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    :ok
  end

  test "req_llm profile can be persisted and produces deterministic fingerprint" do
    profile =
      %LLMProfile{
        id: "req_llm",
        name: "Requirements LLM",
        provider: :openai_compatible,
        model: :"local-model",
        policy_version: "1",
        generation: %{temperature: 0.2, top_p: 1.0, max_output_tokens: 800, seed: 42},
        budgets: %{request_timeout_ms: 60_000, max_retries: 0},
        tools: [],
        stop_list: [],
        tags: ["req"]
      }

    assert {:ok, "req_llm"} = Profiles.put(profile)

    loaded = Profiles.get!("req_llm")
    assert loaded.id == "req_llm"
    assert loaded.provider == :openai_compatible or loaded.provider == "openai_compatible"

    cfg1 = Resolver.resolve(loaded, %{})
    cfg2 = Resolver.resolve(loaded, %{})

    assert cfg1.fingerprint == cfg2.fingerprint
  end
end
