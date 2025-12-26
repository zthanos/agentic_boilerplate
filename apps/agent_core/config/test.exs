# apps/agent_core/config/test.exs (ή root config/test.exs αν κρατάς κεντρικά config)

import Config

config :agent_core, AgentCore.Llm.ProviderRouter,
  openai: AgentCore.Llm.Providers.FakeProvider
