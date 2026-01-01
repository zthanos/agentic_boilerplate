# apps/agent_core/config/test.exs

import Config

# Logger configuration for test environment
config :logger, level: :warning

# ExUnit configuration
ExUnit.start()

config :agent_core, AgentCore.Llm.ProviderRouter,
  openai: AgentCore.Llm.Providers.FakeProvider
