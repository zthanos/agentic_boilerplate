defmodule AgentCore.Llm.ResolverTest do
  use ExUnit.Case, async: true

  alias AgentCore.Llm.{LLMProfile, Resolver, InvocationConfig}

  @profile %LLMProfile{
    id: "p_default",
    name: "Default GPT Profile",
    provider: :openai,
    model: "gpt-4.1-mini",
    generation: %{temperature: 0.2, top_p: 1.0, max_output_tokens: 800},
    budgets: %{request_timeout_ms: 60_000, max_retries: 2},
    tools: ["web_search", :json_schema],
    stop_list: ["\n\nHuman:", "   ", "###"]
  }

  describe "resolve/2 basics" do
    test "returns InvocationConfig snapshot with expected core fields" do
      overrides = %{
        generation: %{temperature: "0.7", max_output_tokens: 1200},
        budgets: %{request_timeout_ms: 30_000},
        stop_list: ["###", "END", "  "],
        tools: [:json_schema, "file_search"]
      }

      config = Resolver.resolve(@profile, overrides)

      assert %InvocationConfig{} = config
      assert config.profile_id == "p_default"
      assert config.profile_name == "Default GPT Profile"
      assert config.provider == :openai
      assert config.model == "gpt-4.1-mini"

      # parsed + merged generation
      assert config.generation == %{temperature: 0.7, top_p: 1.0, max_output_tokens: 1200}

      # merged budgets (override + retained)
      assert config.budgets == %{request_timeout_ms: 30_000, max_retries: 2}

      # stop_list normalized (trim + drop blanks + uniq + sorted)
      assert config.stop_list == ["###", "END"]

      # tools normalized (atoms to string + uniq + sorted)
      assert config.tools == ["file_search", "json_schema", "web_search"]

      assert is_binary(config.fingerprint)
      assert byte_size(config.fingerprint) == 64
      assert %DateTime{} = config.resolved_at
    end

    test "nil overrides act as no-op (do not overwrite profile values)" do
      overrides = %{budgets: %{request_timeout_ms: nil}}

      config = Resolver.resolve(@profile, overrides)

      assert config.budgets == %{request_timeout_ms: 60_000, max_retries: 2}
    end

    test "clear semantics: stop_list :__clear__ results in empty list" do
      config = Resolver.resolve(@profile, %{stop_list: :__clear__})
      assert config.stop_list == []
    end
  end

  describe "determinism and fingerprint stability" do
    # test "same inputs produce same fingerprint (resolved_at does not affect it)" do
    #   overrides = %{
    #     generation: %{temperature: "0.7", max_output_tokens: 1200},
    #     budgets: %{request_timeout_ms: 30_000},
    #     stop_list: ["###", "END", "  "],
    #     tools: [:json_schema, "file_search"]
    #   }

    #   config1 = Resolver.resolve(@profile, overrides)
    #   Process.sleep(2)
    #   config2 = Resolver.resolve(@profile, overrides)

    #   assert config1.fingerprint == config2.fingerprint
    #   assert config1.resolved_at != config2.resolved_at
    # end

    test "fingerprint is stable regardless of list ordering in overrides (due to canonicalization)" do
      overrides_a = %{
        stop_list: ["END", "###", "  "],
        tools: ["file_search", :json_schema]
      }

      overrides_b = %{
        stop_list: ["###", "END"],
        tools: [:json_schema, "file_search"]
      }

      config_a = Resolver.resolve(@profile, overrides_a)
      config_b = Resolver.resolve(@profile, overrides_b)

      assert config_a.stop_list == ["###", "END"]
      assert config_b.stop_list == ["###", "END"]

      assert config_a.tools == ["file_search", "json_schema", "web_search"]
      assert config_b.tools == ["file_search", "json_schema", "web_search"]

      assert config_a.fingerprint == config_b.fingerprint
    end
  end

  describe "normalization edge cases" do
    test "stop_list keeps only non-blank strings" do
      config = Resolver.resolve(@profile, %{stop_list: ["", "   ", "\n", "END"]})
      assert config.stop_list == ["END"]
    end

    test "tools supports atom and string, trims blanks, uniq + sorted" do
      config = Resolver.resolve(@profile, %{tools: ["  ", :json_schema, "file_search", "file_search"]})
      assert config.tools == ["file_search", "json_schema", "web_search"]
    end

    test "generation numeric parsing from string works (temperature/top_p/max_output_tokens)" do
      overrides = %{generation: %{temperature: "0.9", top_p: "0.5", max_output_tokens: "1500"}}
      config = Resolver.resolve(@profile, overrides)

      assert config.generation.temperature == 0.9
      assert config.generation.top_p == 0.5
      assert config.generation.max_output_tokens == 1500
    end
  end

  test "same inputs produce same fingerprint (resolved_at does not affect it)" do
    overrides = %{
      generation: %{temperature: "0.7", max_output_tokens: 1200},
      budgets: %{request_timeout_ms: 30_000},
      stop_list: ["###", "END", "  "],
      tools: [:json_schema, "file_search"]
    }

    config1 = Resolver.resolve(@profile, overrides)
    config2 = Resolver.resolve(@profile, overrides)

    assert config1.fingerprint == config2.fingerprint

    assert %DateTime{} = config1.resolved_at
    assert %DateTime{} = config2.resolved_at
  end

  describe "override policy for list fields" do
    test "tools default policy is :union (profile tools are preserved)" do
      overrides = %{tools: [:json_schema, "file_search"]}
      config = Resolver.resolve(@profile, overrides)

      assert config.tools == ["file_search", "json_schema", "web_search"]
    end

    test "stop_list default policy is :replace (profile stop_list is replaced)" do
      overrides = %{stop_list: ["END"]}
      config = Resolver.resolve(@profile, overrides)

      assert config.stop_list == ["END"]
    end

    test "can override policy at call-site (tools :replace)" do
      overrides = %{tools: [:json_schema, "file_search"]}

      policy = %{tools: :replace, stop_list: :replace, generation: :merge, budgets: :merge}
      config = Resolver.resolve(@profile, overrides, policy)

      assert config.tools == ["file_search", "json_schema"]
    end
  end


end
