# apps/agent_runtime/config/test.llm.exs
config :agent_runtime, :run_store, AgentRuntime.Llm.RunStore.Memory
setup_all do
  Application.put_env(:agent_core, AgentCore.Llm.ProviderRouter,
    openai: AgentCore.Llm.Providers.OpenAICompatible
  )

  on_exit(fn ->
    Application.put_env(:agent_core, AgentCore.Llm.ProviderRouter,
      openai: AgentCore.Llm.Providers.FakeProvider
    )
  end)

  :ok
end
