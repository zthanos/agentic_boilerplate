# apps/agent_core/config/test.exs (ή root config/test.exs αν κρατάς κεντρικά config)

import Config

config :agent_core, AgentCore.Repo,
  database: "data/agent_core_test.sqlite3",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 5

config :agent_core, ecto_repos: [AgentCore.Repo]

config :agent_core, AgentCore.Llm.Runs,
  store: AgentCore.Llm.RunStore.Ecto
