defmodule AgentCore.WorkflowEngine.LlmIntegration do
  @moduledoc """
  LLM integration layer for workflow agents.

  This module provides clean separation between agent management and LLM integration,
  handling workflow result formatting for LLM consumption and managing the integration
  between workflow execution and LLM systems.

  ## Features

  - Workflow result formatting for LLM consumption
  - Clean separation between agent management and LLM integration
  - Support for different LLM integration patterns
  - Configurable result transformation and formatting
  - Integration with existing LLM provider infrastructure

  ## Usage

      # Configure LLM integration for an agent
      llm_config = %{
        provider: :openai,
        model: "gpt-4",
        result_formatter: :history_rag,
        prompt_template: "workflow_result"
      }

      # Format workflow results for LLM consumption
      formatted_result = LlmIntegration.format_for_llm(workflow_result, llm_config)

      # Create LLM request from workflow result
      llm_request = LlmIntegration.create_llm_request(workflow_result, llm_config, context)

  ## Integration Patterns

  The module supports several integration patterns:

  1. **Direct Integration**: Workflow results are directly formatted for LLM consumption
  2. **Template-based**: Results are formatted using configurable templates
  3. **Context Augmentation**: Workflow results augment existing LLM context
  4. **Chain Integration**: Workflow results feed into LLM processing chains

  ## Result Formatting

  Different formatters are available for different workflow types:
  - `:history_rag` - Formats history RAG workflow results for prompt augmentation
  - `:generic` - Generic formatting for any workflow result
  - `:structured` - Structured data formatting for complex workflows
  - Custom formatters can be implemented by providing formatting functions
  """

  alias AgentCore.Llm.{ProviderRequest, InvocationConfig}
  alias AgentCore.WorkflowEngine.WorkflowResult

  @type llm_config :: %{
          required(:provider) => atom(),
          required(:model) => String.t(),
          optional(:result_formatter) => atom() | function(),
          optional(:prompt_template) => String.t(),
          optional(:context_integration) => :augment | :replace | :append,
          optional(:metadata_inclusion) => boolean(),
          optional(:trace_inclusion) => boolean(),
          optional(:custom_options) => map()
        }

  @type formatted_result :: %{
          content: String.t(),
          metadata: map(),
          integration_type: atom(),
          original_result: map()
        }

  @type llm_request_context :: %{
          optional(:existing_messages) => [map()],
          optional(:system_prompt) => String.t(),
          optional(:user_context) => map(),
          optional(:conversation_id) => String.t(),
          optional(:trace_id) => String.t()
        }

  @doc """
  Formats a workflow result for LLM consumption.

  Takes a workflow result and LLM configuration, returning a formatted result
  suitable for integration with LLM systems.

  ## Examples

      iex> workflow_result = %{final_output: %{history_context: "Previous context", augmented_prompt: "Enhanced prompt"}}
      iex> llm_config = %{provider: :openai, model: "gpt-4", result_formatter: :history_rag}
      iex> LlmIntegration.format_for_llm(workflow_result, llm_config)
      %{content: "Enhanced prompt", metadata: %{...}, integration_type: :history_rag, ...}
  """
  @spec format_for_llm(WorkflowResult.t() | map(), llm_config()) :: formatted_result()
  def format_for_llm(workflow_result, llm_config)
      when is_map(workflow_result) and is_map(llm_config) do
    formatter = Map.get(llm_config, :result_formatter, :generic)

    formatted_content = apply_formatter(workflow_result, formatter)

    %{
      content: formatted_content,
      metadata: build_metadata(workflow_result, llm_config),
      integration_type: formatter,
      original_result: workflow_result
    }
  end

  @doc """
  Creates an LLM request from a workflow result and context.

  Combines workflow results with existing context to create a complete LLM request
  suitable for provider execution.

  ## Examples

      iex> workflow_result = %{final_output: %{augmented_prompt: "Enhanced prompt"}}
      iex> llm_config = %{provider: :openai, model: "gpt-4"}
      iex> context = %{existing_messages: [%{role: :user, content: "Hello"}]}
      iex> LlmIntegration.create_llm_request(workflow_result, llm_config, context)
      %ProviderRequest{...}
  """
  @spec create_llm_request(WorkflowResult.t() | map(), llm_config(), llm_request_context()) ::
          ProviderRequest.t()
  def create_llm_request(workflow_result, llm_config, context \\ %{}) do
    formatted_result = format_for_llm(workflow_result, llm_config)

    invocation_config = build_invocation_config(llm_config, context)
    input = build_llm_input(formatted_result, context, llm_config)

    ProviderRequest.new(
      invocation_config,
      input,
      # tools - could be extended based on workflow needs
      [],
      build_request_metadata(formatted_result, context)
    )
  end

  @doc """
  Validates LLM configuration for workflow integration.

  Ensures the LLM configuration contains all required fields and valid values.
  """
  @spec validate_llm_config(llm_config()) :: :ok | {:error, String.t()}
  def validate_llm_config(llm_config) when is_map(llm_config) do
    with :ok <- validate_required_fields(llm_config),
         :ok <- validate_formatter(llm_config),
         :ok <- validate_provider_config(llm_config) do
      :ok
    end
  end

  @doc """
  Registers a custom result formatter.

  Allows registration of custom formatting functions for specific workflow types.

  ## Examples

      iex> formatter_fn = fn workflow_result -> "Custom: " <> inspect(workflow_result.final_output) end
      iex> LlmIntegration.register_formatter(:custom_type, formatter_fn)
      :ok
  """
  @spec register_formatter(atom(), function()) :: :ok
  def register_formatter(formatter_name, formatter_fn)
      when is_atom(formatter_name) and is_function(formatter_fn, 1) do
    :persistent_term.put({__MODULE__, :formatter, formatter_name}, formatter_fn)
    :ok
  end

  @doc """
  Gets available result formatters.
  """
  @spec list_formatters() :: [atom()]
  def list_formatters do
    [:generic, :history_rag, :structured] ++ get_custom_formatters()
  end

  @doc """
  Extracts workflow context for LLM integration.

  Extracts relevant context information from workflow results that can be used
  to enhance LLM interactions.
  """
  @spec extract_workflow_context(WorkflowResult.t() | map()) :: map()
  def extract_workflow_context(workflow_result) when is_map(workflow_result) do
    %{
      workflow_status: get_workflow_status(workflow_result),
      execution_path: get_execution_path(workflow_result),
      key_artifacts: extract_key_artifacts(workflow_result),
      performance_metrics: extract_performance_metrics(workflow_result),
      error_context: extract_error_context(workflow_result)
    }
  end

  # Private Functions - Formatters

  defp apply_formatter(workflow_result, :generic) do
    case workflow_result do
      %{final_output: final_output} when is_map(final_output) ->
        final_output
        |> Map.to_list()
        |> Enum.map(fn {k, v} -> "#{k}: #{format_value(v)}" end)
        |> Enum.join("\n")

      %{final_output: final_output} ->
        format_value(final_output)

      _ ->
        inspect(workflow_result)
    end
  end

  defp apply_formatter(workflow_result, :history_rag) do
    case workflow_result do
      %{final_output: %{augmented_prompt: prompt}} when is_binary(prompt) ->
        prompt

      %{final_output: %{history_context: context, current_message: message}} ->
        if context && String.trim(context) != "" do
          "Context: #{context}\n\nMessage: #{message}"
        else
          message
        end

      %{final_output: _final_output} ->
        # Fallback to generic formatting
        apply_formatter(workflow_result, :generic)

      _ ->
        "No valid history RAG result found"
    end
  end

  defp apply_formatter(workflow_result, :structured) do
    Jason.encode!(workflow_result, pretty: true)
  rescue
    _ -> inspect(workflow_result, pretty: true)
  end

  defp apply_formatter(workflow_result, formatter_name) when is_atom(formatter_name) do
    case :persistent_term.get({__MODULE__, :formatter, formatter_name}, nil) do
      nil -> apply_formatter(workflow_result, :generic)
      formatter_fn -> formatter_fn.(workflow_result)
    end
  end

  defp apply_formatter(workflow_result, formatter_fn) when is_function(formatter_fn, 1) do
    formatter_fn.(workflow_result)
  end

  # Private Functions - Metadata and Configuration

  defp build_metadata(workflow_result, llm_config) do
    base_metadata = %{
      workflow_integration: true,
      formatter_used: Map.get(llm_config, :result_formatter, :generic),
      timestamp: DateTime.utc_now(),
      include_trace: Map.get(llm_config, :trace_inclusion, false)
    }

    if Map.get(llm_config, :metadata_inclusion, true) do
      workflow_metadata = extract_workflow_context(workflow_result)
      Map.merge(base_metadata, workflow_metadata)
    else
      base_metadata
    end
  end

  defp build_invocation_config(llm_config, context) do
    %InvocationConfig{
      profile_id: Map.get(llm_config, :profile_id, "workflow_agent"),
      provider: Map.fetch!(llm_config, :provider),
      model: Map.fetch!(llm_config, :model),
      trace_id: Map.get(context, :trace_id),
      fingerprint: generate_fingerprint(llm_config, context),
      generation: Map.get(llm_config, :generation, %{}),
      budgets: Map.get(llm_config, :budgets, %{}),
      tools: Map.get(llm_config, :tools, []),
      overrides: Map.get(llm_config, :overrides, %{})
    }
  end

  defp build_llm_input(formatted_result, context, llm_config) do
    integration_type = Map.get(llm_config, :context_integration, :augment)

    case integration_type do
      :replace ->
        %{
          type: :chat,
          messages: [%{role: :user, content: formatted_result.content}]
        }

      :append ->
        existing_messages = Map.get(context, :existing_messages, [])
        new_message = %{role: :user, content: formatted_result.content}

        %{
          type: :chat,
          messages: existing_messages ++ [new_message]
        }

      :augment ->
        existing_messages = Map.get(context, :existing_messages, [])
        augmented_messages = augment_messages(existing_messages, formatted_result.content)

        %{
          type: :chat,
          messages: augmented_messages
        }
    end
  end

  defp build_request_metadata(formatted_result, context) do
    %{
      workflow_integration: true,
      integration_type: formatted_result.integration_type,
      conversation_id: Map.get(context, :conversation_id),
      workflow_metadata: formatted_result.metadata
    }
  end

  # Private Functions - Validation

  defp validate_required_fields(llm_config) do
    required_fields = [:provider, :model]

    missing_fields = Enum.reject(required_fields, &Map.has_key?(llm_config, &1))

    if Enum.empty?(missing_fields) do
      :ok
    else
      {:error, "Missing required LLM config fields: #{inspect(missing_fields)}"}
    end
  end

  defp validate_formatter(llm_config) do
    case Map.get(llm_config, :result_formatter) do
      nil ->
        :ok

      formatter when is_atom(formatter) ->
        if formatter in list_formatters() do
          :ok
        else
          {:error, "Unknown formatter: #{formatter}"}
        end

      formatter when is_function(formatter, 1) ->
        :ok

      _ ->
        {:error, "Formatter must be an atom or function/1"}
    end
  end

  defp validate_provider_config(llm_config) do
    provider = Map.get(llm_config, :provider)
    model = Map.get(llm_config, :model)

    cond do
      not is_atom(provider) -> {:error, "Provider must be an atom"}
      not is_binary(model) -> {:error, "Model must be a string"}
      String.trim(model) == "" -> {:error, "Model cannot be empty"}
      true -> :ok
    end
  end

  # Private Functions - Utilities

  defp format_value(value) when is_binary(value), do: value
  defp format_value(value) when is_number(value), do: to_string(value)
  defp format_value(value) when is_atom(value), do: Atom.to_string(value)
  defp format_value(value) when is_list(value), do: Enum.join(value, ", ")
  defp format_value(value), do: inspect(value)

  defp get_custom_formatters do
    try do
      :persistent_term.get()
      |> Enum.filter(fn
        {{module, :formatter, _name}, _fn} when module == __MODULE__ -> true
        _ -> false
      end)
      |> Enum.map(fn {{_module, :formatter, name}, _fn} -> name end)
    rescue
      _ -> []
    end
  end

  defp get_workflow_status(%{status: status}), do: status
  defp get_workflow_status(_), do: :unknown

  defp get_execution_path(%{visited_nodes: nodes}) when is_list(nodes), do: nodes
  defp get_execution_path(_), do: []

  defp extract_key_artifacts(%{final_output: final_output}) when is_map(final_output) do
    final_output
    |> Map.take([:history_context, :augmented_prompt, :query_results, :context_items])
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp extract_key_artifacts(_), do: %{}

  defp extract_performance_metrics(%{trace: trace}) when is_list(trace) do
    %{
      total_steps: length(trace),
      execution_time: calculate_total_time(trace),
      step_performance: extract_step_performance(trace)
    }
  end

  defp extract_performance_metrics(_), do: %{}

  defp extract_error_context(%{error: error}) when not is_nil(error) do
    %{has_error: true, error_details: format_value(error)}
  end

  defp extract_error_context(_), do: %{has_error: false}

  defp calculate_total_time(trace) do
    trace
    |> Enum.map(&Map.get(&1, :duration_ms, 0))
    |> Enum.sum()
  end

  defp extract_step_performance(trace) do
    trace
    |> Enum.map(fn step ->
      %{
        node_id: Map.get(step, :node_id),
        duration_ms: Map.get(step, :duration_ms, 0),
        status: Map.get(step, :status)
      }
    end)
  end

  defp generate_fingerprint(llm_config, context) do
    data = %{
      provider: llm_config.provider,
      model: llm_config.model,
      context_keys: Map.keys(context),
      timestamp: System.system_time(:second)
    }

    :crypto.hash(:sha256, :erlang.term_to_binary(data))
    |> Base.encode16(case: :lower)
    |> String.slice(0, 16)
  end

  defp augment_messages([], content) do
    [%{role: :user, content: content}]
  end

  defp augment_messages(messages, content) do
    # Find the last user message and augment it with workflow content
    case Enum.reverse(messages) do
      [%{role: :user, content: last_content} = last_msg | rest] ->
        augmented_content = "#{content}\n\n#{last_content}"
        augmented_msg = %{last_msg | content: augmented_content}
        Enum.reverse([augmented_msg | rest])

      _ ->
        # No user message found, append as new message
        messages ++ [%{role: :user, content: content}]
    end
  end
end
