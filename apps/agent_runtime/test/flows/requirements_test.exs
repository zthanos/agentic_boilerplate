defmodule AgentRuntime.Flows.RequirementsTest do
  use ExUnit.Case, async: false

  alias AgentCore.Repo
  alias AgentCore.Llm.{LLMProfile, Profiles}
  alias AgentRuntime.Flows.Requirements
  # alias AgentRuntime.Llm.ProfileSelector

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    prev_router = Application.get_env(:agent_runtime, AgentRuntime.Llm.ProviderRouter, [])

    Application.put_env(:agent_runtime, AgentRuntime.Llm.ProviderRouter,
      overrides: %{fake: AgentRuntime.TestSupport.JsonProvider}
    )

    on_exit(fn ->
      Application.put_env(:agent_runtime, AgentRuntime.Llm.ProviderRouter, prev_router)

    end)


    profile =
      %LLMProfile{
        id: "req_llm",
        name: "Req LLM Test",
        provider: :fake,
        model: "test-model",
        policy_version: "1"
      }

    {:ok, _} = Profiles.put(profile)

    :ok
  end

  test "extract uses the requirements profile mapping and returns a ProviderResponse" do
    messages = [
      %{role: :system, content: "Extract requirements."},
      %{role: :user, content: "I need login and MFA."}
    ]


    assert {:ok, json} = Requirements.extract(messages, %{})
    assert get_in(json, ["meta", "version"]) == "1.0"
    assert is_list(json["functional_requirements"])

  end
end
