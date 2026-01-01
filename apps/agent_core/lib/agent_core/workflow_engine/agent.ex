defmodule AgentCore.WorkflowEngine.Agent do
  @moduledoc """
  Agent system that exposes workflows to UI controllers and manages LLM integration.

  The Agent serves as the primary interface between UI controllers and the workflow engine,
  providing workflow selection, execution management, and LLM integration capabilities.

  ## Features

  - Exposes one or more workflows for execution
  - Workflow selection based on request parameters
  - Clean interface for UI controller interaction
  - LLM integration capabilities
  - Request routing and parameter validation

  ## Usage

      # Create an agent with workflows
      agent = Agent.new(%{
        id: "history_agent",
        workflows: [:history_rag],
        default_workflow: :history_rag
      })

      # Execute a workflow through the agent
      request = %{
        workflow_id: :history_rag,
        input: %{current_message: "Hello", conversation_id: "123"}
      }

      case Agent.execute_workflow(agent, request) do
        {:ok, result} -> handle_success(result)
        {:error, reason} -> handle_error(reason)
      end

  ## Agent Configuration

  Agents are configured with:
  - `id`: Unique agent identifier
  - `workflows`: List of workflow IDs this agent can execute
  - `default_workflow`: Default workflow when none specified
  - `llm_integration`: Optional LLM integration configuration
  - `metadata`: Additional agent metadata

  ## Workflow Selection

  The agent selects workflows based on:
  1. Explicit `workflow_id` in the request
  2. Request parameters and routing rules
  3. Default workflow if no specific selection
  4. Validation against agent's available workflows
  """

  alias AgentCore.WorkflowEngine.{Registry, Runtime, LlmIntegration}

  @enforce_keys [:id, :workflows]
  defstruct [
    :id,
    :workflows,
    :default_workflow,
    :llm_integration,
    :metadata,
    routing_rules: []
  ]

  @type agent_id :: String.t() | atom()
  @type workflow_id :: atom() | String.t()
  @type workflow_request :: %{
          optional(:workflow_id) => workflow_id(),
          required(:input) => map(),
          optional(:context) => map(),
          optional(:metadata) => map(),
          optional(:llm_integration) => boolean()
        }
  @type workflow_response :: %{
          status: :ok | :error,
          result: map() | nil,
          error: String.t() | nil,
          agent_id: agent_id(),
          workflow_id: workflow_id() | nil,
          execution_time_ms: non_neg_integer(),
          metadata: map()
        }

  @type routing_rule :: %{
          condition: (map() -> boolean()),
          workflow_id: workflow_id()
        }

  @type t :: %__MODULE__{
          id: agent_id(),
          workflows: [workflow_id()],
          default_workflow: workflow_id() | nil,
          llm_integration: map() | nil,
          metadata: map(),
          routing_rules: [routing_rule()]
        }

  @doc """
  Creates a new agent with the specified configuration.

  ## Examples

      iex> Agent.new(%{id: "test_agent", workflows: [:test_workflow]})
      %Agent{id: "test_agent", workflows: [:test_workflow], ...}

      iex> Agent.new(%{id: "history_agent", workflows: [:history_rag], default_workflow: :history_rag})
      %Agent{id: "history_agent", workflows: [:history_rag], default_workflow: :history_rag, ...}
  """
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      id: Map.fetch!(attrs, :id),
      workflows: Map.fetch!(attrs, :workflows),
      default_workflow: Map.get(attrs, :default_workflow),
      llm_integration: Map.get(attrs, :llm_integration),
      metadata: Map.get(attrs, :metadata, %{}),
      routing_rules: Map.get(attrs, :routing_rules, [])
    }
  end

  @doc """
  Validates an agent configuration.

  Ensures all required fields are present and workflows are available in the registry.
  """
  @spec validate(t()) :: :ok | {:error, String.t()}
  def validate(%__MODULE__{} = agent) do
    with :ok <- validate_required_fields(agent),
         :ok <- validate_workflows_exist(agent),
         :ok <- validate_default_workflow(agent) do
      :ok
    end
  end

  @doc """
  Executes a workflow through the agent interface with optional LLM integration.

  The agent handles workflow selection, validation, execution, result formatting,
  and optional LLM integration based on agent configuration.

  ## Examples

      iex> request = %{workflow_id: :history_rag, input: %{current_message: "Hello"}}
      iex> Agent.execute_workflow(agent, request)
      {:ok, %{status: :ok, result: %{...}, ...}}

      iex> request = %{input: %{current_message: "Hello"}}  # Uses default workflow
      iex> Agent.execute_workflow(agent, request)
      {:ok, %{status: :ok, result: %{...}, ...}}

      # With LLM integration
      iex> request = %{workflow_id: :history_rag, input: %{current_message: "Hello"}, llm_integration: true}
      iex> Agent.execute_workflow(agent, request)
      {:ok, %{status: :ok, result: %{...}, llm_formatted_result: %{...}, ...}}
  """
  @spec execute_workflow(t(), workflow_request()) :: {:ok, workflow_response()} | {:error, String.t()}
  def execute_workflow(%__MODULE__{} = agent, request) when is_map(request) do
    start_time = System.monotonic_time(:millisecond)

    with {:ok, workflow_id} <- select_workflow(agent, request),
         {:ok, spec} <- Registry.get_workflow(workflow_id),
         {:ok, input} <- validate_request_input(request),
         {:ok, workflow_result} <- Runtime.execute(spec, input) do
      execution_time = System.monotonic_time(:millisecond) - start_time

      base_response = %{
        status: :ok,
        result: workflow_result.final_output,
        error: nil,
        agent_id: agent.id,
        workflow_id: workflow_id,
        execution_time_ms: execution_time,
        metadata: %{
          visited_nodes: workflow_result.visited_nodes,
          trace_available: length(workflow_result.trace) > 0,
          context_metadata: Map.get(request, :metadata, %{})
        }
      }

      # Add LLM integration if configured and requested
      response = maybe_add_llm_integration(base_response, workflow_result, agent, request)

      {:ok, response}
    else
      {:error, workflow_result} when is_map(workflow_result) ->
        # Handle workflow execution failure
        execution_time = System.monotonic_time(:millisecond) - start_time

        response = %{
          status: :error,
          result: nil,
          error: format_workflow_error(workflow_result),
          agent_id: agent.id,
          workflow_id: Map.get(request, :workflow_id),
          execution_time_ms: execution_time,
          metadata: %{
            visited_nodes: workflow_result.visited_nodes || [],
            trace_available: length(workflow_result.trace || []) > 0,
            context_metadata: Map.get(request, :metadata, %{})
          }
        }

        {:ok, response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Lists all workflows available through this agent.
  """
  @spec list_workflows(t()) :: [workflow_id()]
  def list_workflows(%__MODULE__{workflows: workflows}), do: workflows

  @doc """
  Checks if the agent can execute a specific workflow.
  """
  @spec can_execute_workflow?(t(), workflow_id()) :: boolean()
  def can_execute_workflow?(%__MODULE__{workflows: workflows}, workflow_id) do
    workflow_id in workflows
  end

  @doc """
  Adds a routing rule to the agent for dynamic workflow selection.

  ## Examples

      iex> rule = %{condition: fn req -> req.input[:type] == "history" end, workflow_id: :history_rag}
      iex> Agent.add_routing_rule(agent, rule)
      %Agent{routing_rules: [rule], ...}
  """
  @spec add_routing_rule(t(), routing_rule()) :: t()
  def add_routing_rule(%__MODULE__{} = agent, rule) when is_map(rule) do
    %{agent | routing_rules: [rule | agent.routing_rules]}
  end

  @doc """
  Creates an LLM request from a workflow result.

  Integrates workflow results with LLM systems by formatting results and creating
  appropriate LLM requests based on agent configuration.

  ## Examples

      iex> workflow_result = %{final_output: %{augmented_prompt: "Enhanced prompt"}}
      iex> context = %{existing_messages: [%{role: :user, content: "Hello"}]}
      iex> Agent.create_llm_request(agent, workflow_result, context)
      %ProviderRequest{...}
  """
  @spec create_llm_request(t(), map(), map()) :: {:ok, map()} | {:error, String.t()}
  def create_llm_request(agent, workflow_result, context \\ %{})

  def create_llm_request(%__MODULE__{llm_integration: nil}, _workflow_result, _context) do
    {:error, "Agent does not have LLM integration configured"}
  end

  def create_llm_request(%__MODULE__{llm_integration: llm_config}, workflow_result, context) do
    case LlmIntegration.validate_llm_config(llm_config) do
      :ok ->
        llm_request = LlmIntegration.create_llm_request(workflow_result, llm_config, context)
        {:ok, llm_request}

      {:error, reason} ->
        {:error, "Invalid LLM configuration: #{reason}"}
    end
  end

  @doc """
  Formats a workflow result for LLM consumption.

  Uses the agent's LLM integration configuration to format workflow results
  appropriately for LLM systems.
  """
  @spec format_for_llm(t(), map()) :: {:ok, map()} | {:error, String.t()}
  def format_for_llm(%__MODULE__{llm_integration: nil}, _workflow_result) do
    {:error, "Agent does not have LLM integration configured"}
  end

  def format_for_llm(%__MODULE__{llm_integration: llm_config}, workflow_result) do
    formatted_result = LlmIntegration.format_for_llm(workflow_result, llm_config)
    {:ok, formatted_result}
  end

  @doc """
  Gets agent information for UI controllers.
  """
  @spec get_info(t()) :: map()
  def get_info(%__MODULE__{} = agent) do
    %{
      id: agent.id,
      workflows: agent.workflows,
      default_workflow: agent.default_workflow,
      has_llm_integration: not is_nil(agent.llm_integration),
      routing_rules_count: length(agent.routing_rules),
      metadata: agent.metadata
    }
  end

  # Private Functions

  defp maybe_add_llm_integration(response, workflow_result, agent, request) do
    should_integrate = Map.get(request, :llm_integration, false) and not is_nil(agent.llm_integration)

    if should_integrate do
      case format_for_llm(agent, workflow_result) do
        {:ok, formatted_result} ->
          Map.put(response, :llm_formatted_result, formatted_result)

        {:error, _reason} ->
          # Don't fail the entire request if LLM formatting fails
          response
      end
    else
      response
    end
  end

  defp validate_required_fields(%__MODULE__{id: nil}), do: {:error, "Agent ID is required"}
  defp validate_required_fields(%__MODULE__{workflows: []}), do: {:error, "At least one workflow is required"}
  defp validate_required_fields(%__MODULE__{workflows: workflows}) when not is_list(workflows), do: {:error, "Workflows must be a list"}
  defp validate_required_fields(_agent), do: :ok

  defp validate_workflows_exist(%__MODULE__{workflows: workflows}) do
    available_workflows = Registry.list_workflows()

    missing_workflows = Enum.reject(workflows, &(&1 in available_workflows))

    if Enum.empty?(missing_workflows) do
      :ok
    else
      {:error, "Workflows not found in registry: #{inspect(missing_workflows)}"}
    end
  end

  defp validate_default_workflow(%__MODULE__{default_workflow: nil}), do: :ok

  defp validate_default_workflow(%__MODULE__{default_workflow: default, workflows: workflows}) do
    if default in workflows do
      :ok
    else
      {:error, "Default workflow '#{default}' is not in agent's workflow list"}
    end
  end

  defp select_workflow(%__MODULE__{} = agent, request) do
    cond do
      # Explicit workflow_id in request
      Map.has_key?(request, :workflow_id) ->
        workflow_id = request.workflow_id

        if workflow_id in agent.workflows do
          {:ok, workflow_id}
        else
          {:error, "Workflow '#{workflow_id}' not available in agent '#{agent.id}'"}
        end

      # Apply routing rules
      length(agent.routing_rules) > 0 ->
        case apply_routing_rules(agent.routing_rules, request) do
          {:ok, workflow_id} -> {:ok, workflow_id}
          :no_match -> use_default_workflow(agent)
        end

      # Use default workflow
      true ->
        use_default_workflow(agent)
    end
  end

  defp apply_routing_rules([], _request), do: :no_match

  defp apply_routing_rules([rule | rest], request) do
    try do
      if rule.condition.(request) do
        {:ok, rule.workflow_id}
      else
        apply_routing_rules(rest, request)
      end
    rescue
      _ -> apply_routing_rules(rest, request)
    end
  end

  defp use_default_workflow(%__MODULE__{default_workflow: nil, workflows: [workflow | _]}) do
    {:ok, workflow}
  end

  defp use_default_workflow(%__MODULE__{default_workflow: default}) when not is_nil(default) do
    {:ok, default}
  end

  defp use_default_workflow(%__MODULE__{workflows: []}) do
    {:error, "No workflows available in agent"}
  end

  defp validate_request_input(%{input: input}) when is_map(input), do: {:ok, input}
  defp validate_request_input(_), do: {:error, "Request must contain 'input' field with map value"}

  defp format_workflow_error(%{error: error}) when is_binary(error), do: error
  defp format_workflow_error(%{error: error}), do: inspect(error)
  defp format_workflow_error(_), do: "Workflow execution failed"
end
