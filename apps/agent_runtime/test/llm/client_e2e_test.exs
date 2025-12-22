defmodule AgentRuntime.Llm.ClientE2ETest do
  use ExUnit.Case, async: false

  alias AgentRuntime.Llm.Client
  alias AgentCore.Llm.{Profiles, LLMProfile}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(AgentCore.Repo)
    # Αν ο κώδικας σου δημιουργεί spawned processes που ακουμπάνε DB:
    Ecto.Adapters.SQL.Sandbox.mode(AgentCore.Repo, {:shared, self()})
    :ok
  end

  test "deterministic execution path via fake provider" do
    profile =
      %LLMProfile{
        id: "fake-profile",
        name: "Fake",
        provider: :fake,
        model: :test_model
      }

    {:ok, _id} = Profiles.put(profile)

    messages = [
      %{role: :system, content: "system"},
      %{role: :user, content: "hello"}
    ]

    {:ok, r1} = Client.chat(profile.id, messages)
    {:ok, r2} = Client.chat(profile.id, messages)

    assert r1.output_text == r2.output_text
  end
end
