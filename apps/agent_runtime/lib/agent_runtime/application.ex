defmodule AgentRuntime.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Create ETS table for tracking async executions
    :ets.new(:agent_executions, [:named_table, :public, :set])

    children = [
      {Finch,
       name: AgentRuntimeFinch,
       pools: %{
         # LM Studio / local OpenAI-compatible
         "http://localhost:1234" => [
           size: 10,
           count: 1
         ]
       }},
      # Workflow execution manager
      AgentRuntime.Workflows.ExecutionManager,
      # Provider registry
      AgentRuntime.Providers.Registry,
      # Tool registry
      AgentRuntime.Tools.Registry
      # Starts a worker by calling: AgentRuntime.Worker.start_link(arg)
      # {AgentRuntime.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: AgentRuntime.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
