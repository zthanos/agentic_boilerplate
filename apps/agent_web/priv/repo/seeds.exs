# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     AgentWeb.Repo.insert!(%AgentWeb.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias AgentCore.Llm.{LLMProfile, Profiles}

req_llm =
  %AgentCore.Llm.LLMProfile{
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



embeddings_nomic_v15 =
  %AgentCore.Llm.LLMProfile{
    id: "embeddings_nomic_v15",
    name: "Embeddings - Nomic v1.5 (LM Studio)",
    enabled: true,
    provider: :openai_compatible,
    model: "text-embedding-nomic-embed-text-v1.5",
    policy_version: "1",
    # embeddings endpoints αγνοούν συνήθως generation params — κρατάμε ουδέτερα
    generation: %{temperature: 0.0, top_p: 1.0, max_output_tokens: 1, seed: 42},
    budgets: %{request_timeout_ms: 60_000, max_retries: 0},
    tools: [],
    stop_list: [],
    tags: ["embeddings", "rag", "memory", "nomic", "lmstudio", "dim:768"]
  }

case Profiles.put(embeddings_nomic_v15) do
  {:ok, _} -> IO.puts("Seeded profile: embeddings_nomic_v15")
  {:error, err} -> IO.inspect(err, label: "Failed to seed embeddings_nomic_v15")
end
