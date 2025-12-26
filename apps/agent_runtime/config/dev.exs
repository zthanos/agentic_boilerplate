config :agent_runtime, AgentRuntime.Llm.ProfileSelector,
  default: "chat_llm",
  mappings: %{
    requirements: "req_llm"
  }

  config :agent_runtime, AgentRuntime.Llm.ModelResolver,
  openai_compatible: %{
    local: "lmstudio-community/Meta-Llama-3-8B-Instruct",
    gpt4mini: "gpt-4o-mini"
  }
