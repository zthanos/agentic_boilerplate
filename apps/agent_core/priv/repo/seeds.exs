alias AgentCore.Llm.{LLMProfile, Profiles}

req_llm =
  %LLMProfile{
    id: "req_llm",
    name: "Requirements LLM",
    enabled: true,
    provider: :openai_compatible,
    model: "openai/gpt-oss-20b",
    policy_version: "1",
    generation: %{temperature: 0.2, top_p: 1.0, max_output_tokens: 1000, seed: 42},
    budgets: %{request_timeout_ms: 60_000, max_retries: 0},
    tools: [],
    stop_list: [],
    tags: ["req", "requirements", "extraction"]
  }

case Profiles.put(req_llm) do
  {:ok, _} -> IO.puts("Seeded profile: req_llm")
  {:error, err} -> IO.inspect(err, label: "Failed to seed req_llm")
end
