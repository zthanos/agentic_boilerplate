defmodule AgentCore.Llm.ProviderContractTest do
  use ExUnit.Case, async: true

  alias AgentCore.Llm.{ProviderContract, InvocationConfig, ProviderRequest}

  test "build_request returns canonical metadata with expected fields" do
    cfg = %InvocationConfig{
      fingerprint: "fp",
      trace_id: "t1",
      profile_id: "p1",
      provider: :openai,
      model: :gpt_test,
      policy_version: "1",
      tools: []
    }

    req = ProviderContract.build_request(cfg, %{type: :completion, prompt: "hi"})
    assert %ProviderRequest{} = req

    assert req.metadata["fingerprint"] == "fp"
    assert req.metadata["trace_id"] == "t1"
    assert req.metadata["profile_id"] == "p1"
    assert req.metadata["provider"] == "openai"
    assert req.metadata["model"] == "gpt_test"
    assert req.metadata["policy_version"] == "1"
  end
end
