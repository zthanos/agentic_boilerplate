defmodule AgentRuntime.Llm.ProviderRegistryTest do
  use ExUnit.Case

  alias AgentRuntime.Llm.ProviderRegistry

  test "resolves openai_compatible adapter" do
    assert {:ok, mod} = ProviderRegistry.adapter(:openai_compatible)
    assert is_atom(mod)
  end

  test "returns error for unsupported provider" do
    assert {:error, _} = ProviderRegistry.adapter(:unknown)
  end
end
