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
alias AgentCore.Llm.Plan.Definition
alias AgentWeb.Llm.PlanStoreEcto
alias AgentCore.Llm.Agent.Definition, as: AgentDef
alias AgentWeb.Llm.AgentStoreEcto

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

plan =
  Definition.new(%{
    id: "history_rag",
    version: 1,
    name: "History RAG",
    policies: %{
      "retrieval" => %{"top_k" => 8, "min_score" => 0.78},
      "steps" => %{
        "assess_need_for_history" => %{
          "system_prompt" => """
          Analyze if this user message needs historical context from the conversation.

          IMPORTANT: This conversation already has history. Previous messages exist in the database.
          Your job is to decide what search query to use to retrieve that history.

          Return ONLY valid JSON:
          {
          "query": string | null
          }

          Decision rules:
          1. If the message is a greeting or introduction (first message) → null
          2. If the message asks about or references something previously discussed → MUST return query
          3. If the message continues a topic, asks follow-up questions → MUST return query
          4. If unsure, return a query (better to have context than miss it)
          5. Only return null for completely standalone, context-free messages

          Query guidelines:
          - Extract key nouns, entities, topics
          - 3-8 words max
          - No quotes, just plain text
          - Focus on what would match in vector search

          Examples:
          Input: "What's my job?"
          Output: {"query": "user's job occupation"}

          Input: "Tell me about yourself"
          Output: {"query": "assistant introduction description"}

          Input: "Hello"
          Output: {"query": null}
          """
        },
        "assess_need_for_clarification" => %{
          "system_prompt" => """
          You are deciding whether a user's request is clear enough to execute.

          Return ONLY valid JSON.

          Schema:
          {
          "needs_clarification": boolean,
          "question": string | null
          }

          Core rules:
          - Default to needs_clarification = false. Ask for clarification ONLY as a last resort.
          - If the request is answerable with reasonable assumptions, proceed (needs_clarification=false).
          - If the user message is empty or nonsensical, ask one short clarification question.

          Context rules (IMPORTANT):
          - You may be given additional context messages (e.g., retrieved memory or working context).
          If such context is present, you MUST use it to resolve references (it/that/this/they) and follow-ups.
          - If the user asks a follow-up, assume it refers to the immediately prior topic in the provided context.
          - Do NOT ask "what do you mean by it?" if the provided context gives a plausible antecedent.

          Comparison questions:
          - If the user asks "How does X compare with Y?" and context provides info about X,
          you can answer even if Y is not in the context - the assistant knows about Y.
          - Only ask for clarification if BOTH X and Y are unclear.

          When to ask clarification:
          - Ask clarification only if you genuinely cannot identify what the user is asking even after using the provided context.
          - If clarification is needed, ask exactly ONE short, specific question.

          Output rules:
          - If needs_clarification = false -> question MUST be null.
          - If needs_clarification = true  -> question MUST be a single short question.

          Examples:
          - "how can I call you?" -> needs_clarification: false
          - "what do you prefer?" -> needs_clarification: false (use context)
          - "yes" -> needs_clarification: false (use context)
          - "you choose" -> needs_clarification: false (use context)
          - "How does that compare with SSE?" -> needs_clarification: false (context has "that", SSE is known)
          - "" -> needs_clarification: true, question: "What would you like to know?"
          - "I need help with..." -> needs_clarification: true, question: "What specifically do you need help with?"
          """
        }
      }
    },
    steps: [
      "AgentRuntime.Llm.Plan.Steps.WorkflowHistoryStep",
      "AgentRuntime.Llm.Plan.Steps.RetrieveMemoryStep",
      "AgentRuntime.Llm.Plan.Steps.AssessNeedForClarificationStep",
      "AgentRuntime.Llm.Plan.Steps.ExecutePromptStep"
    ]
  })

{:ok, plan} = Definition.validate(plan)

case PlanStoreEcto.get(plan.id, plan.version) do
  {:ok, _} -> :ok
  {:error, :not_found} -> PlanStoreEcto.put(plan)
end

agent =
  AgentDef.new(%{
    id: "arch_assistant",
    version: 1,
    name: "Architect Assistant",
    plan: %{"id" => "history_rag", "version" => 1},
    profiles: %{
      "execution_profile_id" => "req_llm",
      "assessor_profile_id" => "req_llm"
    },
    prompts: %{
      "system" =>
        "You are a policy-driven Architect Assistant Agent. Follow the plan and policies strictly."
    },
    policies: %{}
  })

{:ok, agent} = AgentDef.validate(agent)

case AgentStoreEcto.get(agent.id, agent.version) do
  {:ok, _} -> :ok
  {:error, :not_found} -> AgentStoreEcto.put(agent)
end
