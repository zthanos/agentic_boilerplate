defmodule AgentRuntime.Llm.ExecutorE2ETest do
  use ExUnit.Case

  @tag :e2e
  test "executes full chain against LM Studio" do
    unless System.get_env("LMSTUDIO_E2E") == "1" do
      IO.puts("Skipping LM Studio E2E. Set LMSTUDIO_E2E=1 to run.")
      :ok
    else
      profile = %{
        provider: :openai_compatible,
        model: :local,
        generation: %{}
      }

      assert {:ok, resp} =
               AgentRuntime.Llm.Executor.execute(profile, %{}, %{
                 type: :chat,
                 messages: [%{role: :user, content: "hi"}]
               })

      assert is_binary(resp.output)
    end
  end
end
