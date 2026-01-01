# apps/agent_runtime/test/test_helper.exs
# ExUnit.start()
Code.require_file("support/json_provider.exs", __DIR__)

Mox.defmock(AgentRuntime.ExecutorMock, for: AgentRuntime.Llm.ExecutorBehaviour)
Mox.defmock(AgentRuntime.MemoryStoreMock, for: AgentRuntime.MemoryStoreBehaviour)

# Mox.set_mox_global()
