defmodule AgentRuntime.LmStudioIntegrationTest do
  use ExUnit.Case, async: false

  alias AgentCore.Repo
  alias AgentCore.Llm.{LLMProfile, Profiles}
  alias AgentRuntime.Llm.Client

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    :ok
  end

  @tag :lm_studio
  test "chat via OpenAI-compatible provider (LM Studio)" do
    # Δεν θέλουμε αυτό το test να τρέχει σε CI by default.
    # Το ενεργοποιείς όταν έχεις LM Studio server running.
    if System.get_env("LMSTUDIO_E2E") != "1" do
      IO.puts("Skipping LM Studio E2E. Set LMSTUDIO_E2E=1 to run.")
      assert true
    else
      # Προφίλ που δείχνει στον openai_compatible provider
      profile =
        %LLMProfile{
          id: "lm_e2e",
          name: "LM Studio (E2E)",
          provider: :openai_compatible,
          # Βάλε εδώ το actual model id που έχεις φορτώσει στο LM Studio.
          # Αν το LM Studio το αγνοεί, πάλι συνήθως δεν θα αποτύχει.
          model: "local-model"
        }

      {:ok, _} = Profiles.put(profile)

      messages = [
        %{role: :system, content: "You are a concise assistant."},
        %{role: :user, content: "Reply with exactly: pong"}
      ]

      assert {:ok, resp} = Client.chat(profile.id, messages, %{})
      assert is_binary(resp.output_text)
      assert String.downcase(resp.output_text) =~ "pong"
    end
  end
end
