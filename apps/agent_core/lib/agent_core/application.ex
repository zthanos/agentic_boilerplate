defmodule AgentCore.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Workflow Engine Registry
      AgentCore.WorkflowEngine.Registry

      # Starts a worker by calling: AgentCore.Worker.start_link(arg)
      # {AgentCore.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: AgentCore.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        # Register the history workflow after the registry starts
        register_default_workflows()
        {:ok, pid}

      error ->
        error
    end
  end

  # Register default workflows with the registry
  defp register_default_workflows do
    # Import the history workflow specification
    alias AgentCore.WorkflowEngine.HistoryWorkflow

    # Register the history RAG workflow
    case HistoryWorkflow.register() do
      :ok ->
        :ok

      {:error, reason} ->
        # Log error but don't crash the application
        require Logger
        Logger.error("Failed to register history workflow: #{inspect(reason)}")
        :ok
    end
  end
end
