defmodule AgentCore.Llm.ProfileStoreEctoTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias AgentCore.Repo
  alias AgentCore.Llm.ProfileStore.Ecto, as: ProfileStoreEcto
  alias AgentCore.Llm.LLMProfile

  setup do
    # Checkout a connection from the sandbox for each test
    :ok = Sandbox.checkout(Repo)

    # If tests are async: true, you need shared mode per-process.
    # Here we keep async: false, but leaving this doesn't hurt.
    Sandbox.mode(Repo, {:shared, self()})

    :ok
  end

  describe "get/1" do
    test "returns :error when profile not found" do
      assert :error == ProfileStoreEcto.get("missing-profile-id")
    end
  end

  describe "put/1 + get/1" do
    test "persists and retrieves a profile" do
      profile = %LLMProfile{
        id: "p1",
        name: "Profile 1",
        enabled: true,
        provider: :openai,
        model: :gpt_4o_mini,
        policy_version: "v1",
        generation: %{"temperature" => 0.7, "max_output_tokens" => 1200},
        budgets: %{"request_timeout_ms" => 10_000, "max_retries" => 2},
        tools: ["web_search", :calculator],
        stop_list: ["###", "END"],
        tags: ["test", "smoke"]
      }

      assert {:ok, "p1"} = ProfileStoreEcto.put(profile)

      assert {:ok, %LLMProfile{} = loaded} = ProfileStoreEcto.get("p1")

      assert loaded.id == "p1"
      assert loaded.name == "Profile 1"
      assert loaded.enabled == true
      assert loaded.provider == :openai
      assert loaded.model == :gpt_4o_mini
      assert loaded.policy_version == "v1"

      assert loaded.generation == profile.generation
      assert loaded.budgets == profile.budgets

      # Stored as strings in DB mapping
      assert Enum.sort(loaded.tools) == Enum.sort(Enum.map(profile.tools, &to_string/1))
      assert Enum.sort(loaded.stop_list) == Enum.sort(profile.stop_list)
      assert Enum.sort(loaded.tags) == Enum.sort(profile.tags)
    end

    test "put/1 updates an existing profile (upsert by id)" do
      p1 =
        %LLMProfile{
          id: "p-upsert",
          name: "Original",
          enabled: true,
          provider: :openai,
          model: :gpt_4o_mini,
          generation: %{"temperature" => 0.2},
          budgets: %{},
          tools: ["t1"],
          stop_list: ["A"],
          tags: ["x"]
        }

      assert {:ok, "p-upsert"} = ProfileStoreEcto.put(p1)

      assert {:ok, loaded1} = ProfileStoreEcto.get("p-upsert")
      assert loaded1.name == "Original"
      assert loaded1.generation == %{"temperature" => 0.2}

      p2 = %LLMProfile{p1 | name: "Updated", generation: %{"temperature" => 0.9}, tools: ["t2", "t3"]}
      assert {:ok, "p-upsert"} = ProfileStoreEcto.put(p2)

      assert {:ok, loaded2} = ProfileStoreEcto.get("p-upsert")
      assert loaded2.name == "Updated"
      assert loaded2.generation == %{"temperature" => 0.9}
      assert Enum.sort(loaded2.tools) == Enum.sort(["t2", "t3"])
    end
  end

  describe "list/1" do
    test "returns all profiles when no filter is provided" do
      assert {:ok, _} =
               ProfileStoreEcto.put(%LLMProfile{
                 id: "l1",
                 name: "L1",
                 enabled: true,
                 provider: :openai,
                 model: :gpt_4o_mini,
                 generation: %{},
                 budgets: %{},
                 tools: [],
                 stop_list: [],
                 tags: []
               })

      assert {:ok, _} =
               ProfileStoreEcto.put(%LLMProfile{
                 id: "l2",
                 name: "L2",
                 enabled: false,
                 provider: :openai,
                 model: :gpt_4o_mini,
                 generation: %{},
                 budgets: %{},
                 tools: [],
                 stop_list: [],
                 tags: []
               })

      ids =
        ProfileStoreEcto.list()
        |> Enum.map(& &1.id)
        |> Enum.sort()

      assert ids == ["l1", "l2"]
    end

    test "filters by enabled: true/false" do
      assert {:ok, _} =
               ProfileStoreEcto.put(%LLMProfile{
                 id: "e1",
                 name: "Enabled",
                 enabled: true,
                 provider: :openai,
                 model: :gpt_4o_mini,
                 generation: %{},
                 budgets: %{},
                 tools: [],
                 stop_list: [],
                 tags: []
               })

      assert {:ok, _} =
               ProfileStoreEcto.put(%LLMProfile{
                 id: "e2",
                 name: "Disabled",
                 enabled: false,
                 provider: :openai,
                 model: :gpt_4o_mini,
                 generation: %{},
                 budgets: %{},
                 tools: [],
                 stop_list: [],
                 tags: []
               })

      enabled_ids =
        ProfileStoreEcto.list(enabled: true)
        |> Enum.map(& &1.id)

      disabled_ids =
        ProfileStoreEcto.list(enabled: false)
        |> Enum.map(& &1.id)

      assert enabled_ids == ["e1"]
      assert disabled_ids == ["e2"]
    end
  end
end
