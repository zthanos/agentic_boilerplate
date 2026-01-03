defmodule AgentRuntime.Agent do
  @moduledoc """
  Main orchestration point for agent execution.

  This module provides the primary interface for executing agent requests,
  coordinating between workflows, tools, providers, and data stores.
  It serves as the main entry point for the runtime layer.
  """

  alias AgentCore.{Runs, Profiles, Workflows, Tools, Providers}
  alias AgentCore.Workflows.{Spec, Context}
  alias AgentRuntime.Workflows.Engine, as: WorkflowEngine
  alias AgentRuntime.Tools.{Executor, Registry}
  alias AgentRuntime.Providers.Client

  require Logger

  @type request :: map()
  @type response :: map()
  @type execution_options :: keyword()
  @type agent_result :: {:ok, response()} | {:error, term()}

  @doc """
  Executes an agent request.

  This is the main entry point for agent execution. It handles:
  - Request validation and routing
  - Profile resolution and configuration
  - Workflow/tool/provider execution
  - Response formatting and error handling

  ## Parameters

  - `request` - The agent request containing:
    - `:type` - Request type (:workflow, :tool, :provider, :chat)
    - `:profile_id` - Profile to use for execution
    - `:input` - Request input data
    - Additional type-specific parameters

  - `opts` - Execution options:
    - `:timeout` - Maximum execution time
    - `:trace` - Enable execution tracing
    - `:async` - Execute asynchronously

  ## Returns

  - `{:ok, response}` - Request executed successfully
  - `{:error, reason}` - Request execution failed

  ## Examples

      # Execute a workflow
      request = %{
        type: :workflow,
        workflow_id: :history_rag,
        profile_id: "default",
        input: %{message: "What did we discuss about pricing?"}
      }

      {:ok, response} = AgentRuntime.Agent.execute_request(request)

      # Execute a tool
      request = %{
        type: :tool,
        tool_name: "web_search",
        profile_id: "default",
        input: %{query: "latest AI news"}
      }

      {:ok, response} = AgentRuntime.Agent.execute_request(request)
  """
  @spec execute_request(request(), execution_options()) :: agent_result()
  def execute_request(request, opts \\ []) do
    Logger.info("Executing agent request",
      type: Map.get(request, :type),
      profile_id: Map.get(request, :profile_id)
    )

    with {:ok, validated_request} <- validate_request(request),
         {:ok, profile} <- resolve_profile(validated_request),
         {:ok, run_id} <- create_run(validated_request, profile) do
      # Mark run as started
      mark_run_started(run_id)

      # Execute based on request type
      result =
        case validated_request.type do
          :workflow -> execute_workflow_request(validated_request, profile, opts)
          :tool -> execute_tool_request(validated_request, profile, opts)
          :provider -> execute_provider_request(validated_request, profile, opts)
          :chat -> execute_chat_request(validated_request, profile, opts)
        end

      # Update run with result
      case result do
        {:ok, response} ->
          mark_run_completed(run_id, response)
          {:ok, response}

        {:error, reason} ->
          mark_run_failed(run_id, reason)
          {:error, reason}
      end
    else
      {:error, reason} ->
        Logger.error("Agent request failed", reason: inspect(reason))
        {:error, reason}
    end
  end

  @doc """
  Executes an agent request asynchronously.

  ## Parameters

  - `request` - The agent request
  - `opts` - Execution options

  ## Returns

  - `{:ok, execution_id}` - Async execution started
  - `{:error, reason}` - Failed to start execution
  """
  @spec execute_request_async(request(), execution_options()) ::
          {:ok, String.t()} | {:error, term()}
  def execute_request_async(request, opts \\ []) do
    task =
      Task.async(fn ->
        execute_request(request, opts)
      end)

    execution_id = generate_execution_id()

    # Store task reference for status checking
    :ets.insert(:agent_executions, {execution_id, task})

    {:ok, execution_id}
  end

  @doc """
  Gets the status of an asynchronous execution.
  """
  @spec get_execution_status(String.t()) ::
          {:ok, :running | :completed | :failed, map()} | {:error, :not_found}
  def get_execution_status(execution_id) do
    case :ets.lookup(:agent_executions, execution_id) do
      [{^execution_id, task}] ->
        case Task.yield(task, 0) do
          nil -> {:ok, :running, %{}}
          {:ok, {:ok, result}} -> {:ok, :completed, result}
          {:ok, {:error, reason}} -> {:ok, :failed, %{error: reason}}
          {:exit, reason} -> {:ok, :failed, %{error: {:task_exit, reason}}}
        end

      [] ->
        {:error, :not_found}
    end
  end

  # Private execution functions

  defp execute_workflow_request(request, profile, opts) do
    workflow_id = Map.get(request, :workflow_id)
    input = Map.get(request, :input, %{})

    Logger.info("Executing workflow", workflow_id: workflow_id)

    with {:ok, spec} <- get_workflow_spec(workflow_id),
         {:ok, context} <- create_workflow_context(input, profile, opts) do
      if Keyword.get(opts, :async, false) do
        WorkflowEngine.execute_async(spec, context, opts)
      else
        WorkflowEngine.execute(spec, context, opts)
      end
    end
  end

  defp execute_tool_request(request, profile, opts) do
    tool_name = Map.get(request, :tool_name)
    input = Map.get(request, :input, %{})

    Logger.info("Executing tool", tool_name: tool_name)

    with {:ok, tool_module} <- Registry.get_tool(tool_name),
         {:ok, execution_context} <- create_tool_context(input, profile, opts) do
      Executor.execute_tool(tool_module, input, execution_context)
    end
  end

  defp execute_provider_request(request, profile, opts) do
    provider_request = Map.get(request, :provider_request)

    Logger.info("Executing provider request", provider: provider_request.provider)

    with {:ok, provider_config} <- get_provider_config(profile, provider_request.provider) do
      Client.execute_request(provider_request, provider_config, opts)
    end
  end

  defp execute_chat_request(request, profile, opts) do
    messages = Map.get(request, :messages, [])

    Logger.info("Executing chat request", message_count: length(messages))

    # For chat requests, we typically use a default workflow or direct provider call
    chat_workflow_id = Map.get(request, :workflow_id, :default_chat)

    workflow_request = %{
      type: :workflow,
      workflow_id: chat_workflow_id,
      profile_id: request.profile_id,
      input: %{messages: messages}
    }

    execute_workflow_request(workflow_request, profile, opts)
  end

  # Helper functions

  defp validate_request(request) when is_map(request) do
    required_fields = [:type, :profile_id]

    missing_fields =
      Enum.filter(required_fields, fn field ->
        not Map.has_key?(request, field)
      end)

    if missing_fields == [] do
      {:ok, request}
    else
      {:error, {:missing_required_fields, missing_fields}}
    end
  end

  defp validate_request(_), do: {:error, :invalid_request_format}

  defp resolve_profile(%{profile_id: profile_id}) do
    store = get_profile_store()

    case store.get(profile_id) do
      {:ok, profile} -> {:ok, profile}
      {:error, :not_found} -> {:error, {:profile_not_found, profile_id}}
      {:error, reason} -> {:error, {:profile_resolution_failed, reason}}
    end
  end

  defp create_run(request, profile) do
    run_attrs = %{
      id: generate_run_id(),
      trace_id: generate_trace_id(),
      fingerprint: generate_fingerprint(request, profile),
      profile_id: profile.id,
      status: :pending,
      created_at: DateTime.utc_now()
    }

    case Runs.new(run_attrs) do
      {:ok, run} ->
        store = get_run_store()

        case store.create(run) do
          {:ok, run_id} -> {:ok, run_id}
          {:error, reason} -> {:error, {:run_creation_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:run_validation_failed, reason}}
    end
  end

  defp mark_run_started(run_id) do
    store = get_run_store()
    store.mark_started(run_id)
  end

  defp mark_run_completed(run_id, outcome) do
    store = get_run_store()
    store.mark_completed(run_id, outcome)
  end

  defp mark_run_failed(run_id, error) do
    store = get_run_store()
    store.mark_failed(run_id, error, %{})
  end

  defp create_workflow_context(input, profile, opts) do
    context = Context.new(input)

    context =
      context
      |> Context.put_metadata(:profile_id, profile.id)
      |> Context.put_metadata(:execution_options, opts)
      |> Context.put_metadata(:created_at, DateTime.utc_now())

    {:ok, context}
  end

  defp create_tool_context(input, profile, opts) do
    context = %{
      profile_id: profile.id,
      execution_options: opts,
      created_at: DateTime.utc_now(),
      input: input
    }

    {:ok, context}
  end

  defp get_workflow_spec(workflow_id) do
    # This would typically come from a workflow registry
    # For now, return a simple error
    {:error, {:workflow_not_found, workflow_id}}
  end

  defp get_provider_config(profile, provider) do
    # Extract provider configuration from profile
    case Map.get(profile, :provider_configs, %{}) do
      %{^provider => config} -> {:ok, config}
      _ -> {:error, {:provider_config_not_found, provider}}
    end
  end

  defp get_run_store do
    Application.get_env(:agent_runtime, :run_store, AgentRuntime.Stores.RunStore)
  end

  defp get_profile_store do
    Application.get_env(:agent_runtime, :profile_store, AgentRuntime.Stores.ProfileStore)
  end

  defp generate_run_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  defp generate_execution_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp generate_trace_id do
    Ecto.UUID.generate()
  end

  defp generate_fingerprint(request, profile) do
    # Create a fingerprint based on request type and profile
    data = "#{request.type}-#{profile.id}-#{DateTime.utc_now() |> DateTime.to_unix()}"
    :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)
  end

  defp generate_fingerprint_from_attrs(attrs) do
    # Create a fingerprint based on attributes (must be exactly 64 characters)
    data = "#{Map.get(attrs, :profile_id, "unknown")}-#{DateTime.utc_now() |> DateTime.to_unix()}"
    :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)
  end

  defp generate_id do
    Ecto.UUID.generate()
  end

  # Public API methods for integration testing

  @doc """
  Creates a new profile.
  """
  @spec create_profile(map()) :: {:ok, Profiles.t()} | {:error, term()}
  def create_profile(attrs) do
    # Generate ID if not provided
    attrs_with_id = Map.put_new(attrs, :id, generate_id())

    with {:ok, profile} <- Profiles.new(attrs_with_id) do
      store = get_profile_store()

      case store.create(profile) do
        {:ok, profile_id} ->
          # Return the full profile with the ID
          {:ok, %{profile | id: profile_id}}

        {:error, _} = error ->
          error
      end
    end
  end

  @doc """
  Gets a profile by ID.
  """
  @spec get_profile(String.t()) :: {:ok, Profiles.t()} | {:error, term()}
  def get_profile(profile_id) do
    store = get_profile_store()
    store.get(profile_id)
  end

  @doc """
  Creates a new run.
  """
  @spec create_run(map()) :: {:ok, Runs.t()} | {:error, term()}
  def create_run(attrs) do
    # Generate required fields if not provided
    attrs_with_defaults =
      attrs
      |> Map.put_new(:id, generate_id())
      |> Map.put_new(:trace_id, generate_trace_id())
      |> Map.put_new(:fingerprint, generate_fingerprint_from_attrs(attrs))
      |> Map.put_new(:resolved_at, DateTime.utc_now())
      |> Map.put_new(:provider, Map.get(attrs, :provider, :openai))
      |> Map.put_new(:model, Map.get(attrs, :model, "gpt-3.5-turbo"))
      |> Map.put_new(:policy_version, "1.0")

    with {:ok, run} <- Runs.new(attrs_with_defaults) do
      store = get_run_store()

      case store.create(run) do
        {:ok, run_id} ->
          # Return the full run with the ID
          {:ok, %{run | id: run_id}}

        {:error, _} = error ->
          error
      end
    end
  end

  @doc """
  Gets a run by ID.
  """
  @spec get_run(String.t()) :: {:ok, Runs.t()} | {:error, term()}
  def get_run(run_id) do
    store = get_run_store()
    store.get(run_id)
  end

  @doc """
  Updates a run.
  """
  @spec update_run(String.t(), map()) :: {:ok, Runs.t()} | {:error, term()}
  def update_run(run_id, attrs) do
    store = get_run_store()
    store.update(run_id, attrs)
  end
end
