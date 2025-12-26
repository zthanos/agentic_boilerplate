defmodule AgentRuntime.Llm.ModelResolverTest do
  use ExUnit.Case, async: false

  alias AgentRuntime.Llm.ModelResolver

  setup do
    prev = Application.get_env(:agent_runtime, ModelResolver)

    on_exit(fn ->
      if is_nil(prev), do: Application.delete_env(:agent_runtime, ModelResolver), else: Application.put_env(:agent_runtime, ModelResolver, prev)
    end)

    :ok
  end

  test "returns string model as-is" do
    assert ModelResolver.resolve(:openai_compatible, "gpt-4o-mini") == "gpt-4o-mini"
  end

  test "maps atom model via provider mapping" do
    Application.put_env(:agent_runtime, ModelResolver,
      openai_compatible: %{local: "lmstudio-model"}
    )

    assert ModelResolver.resolve(:openai_compatible, :local) == "lmstudio-model"
  end

  test "falls back to atom string when mapping missing" do
    Application.put_env(:agent_runtime, ModelResolver, openai_compatible: %{})
    assert ModelResolver.resolve(:openai_compatible, :local) == "local"
  end
end
