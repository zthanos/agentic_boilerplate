defmodule AgentCore.WorkflowEngine.LlmIntegrationTest do
  use ExUnit.Case, async: true
  alias AgentCore.WorkflowEngine.LlmIntegration

  describe "result formatting" do
    test "formats generic workflow results" do
      workflow_result = %{
        final_output: %{
          message: "Hello world",
          count: 42,
          status: :success
        }
      }

      llm_config = %{
        provider: :openai,
        model: "gpt-4",
        result_formatter: :generic
      }

      formatted = LlmIntegration.format_for_llm(workflow_result, llm_config)

      assert formatted.integration_type == :generic
      assert is_binary(formatted.content)
      assert String.contains?(formatted.content, "Hello world")
      assert String.contains?(formatted.content, "42")
      assert formatted.original_result == workflow_result
    end

    test "formats history RAG workflow results" do
      workflow_result = %{
        final_output: %{
          augmented_prompt: "Context: Previous conversation\n\nMessage: Hello",
          history_items_used: 3
        }
      }

      llm_config = %{
        provider: :openai,
        model: "gpt-4",
        result_formatter: :history_rag
      }

      formatted = LlmIntegration.format_for_llm(workflow_result, llm_config)

      assert formatted.integration_type == :history_rag
      assert formatted.content == "Context: Previous conversation\n\nMessage: Hello"
      assert formatted.original_result == workflow_result
    end

    test "formats structured workflow results" do
      workflow_result = %{
        final_output: %{
          data: [1, 2, 3],
          metadata: %{version: "1.0"}
        }
      }

      llm_config = %{
        provider: :openai,
        model: "gpt-4",
        result_formatter: :structured
      }

      formatted = LlmIntegration.format_for_llm(workflow_result, llm_config)

      assert formatted.integration_type == :structured
      assert is_binary(formatted.content)
      # Should be valid JSON
      assert {:ok, _} = Jason.decode(formatted.content)
    end

    test "uses custom formatter function" do
      workflow_result = %{final_output: %{value: "test"}}

      custom_formatter = fn result ->
        "Custom: #{result.final_output.value}"
      end

      llm_config = %{
        provider: :openai,
        model: "gpt-4",
        result_formatter: custom_formatter
      }

      formatted = LlmIntegration.format_for_llm(workflow_result, llm_config)

      assert formatted.content == "Custom: test"
    end
  end

  describe "LLM request creation" do
    test "creates basic LLM request" do
      workflow_result = %{
        final_output: %{augmented_prompt: "Enhanced prompt"}
      }

      llm_config = %{
        provider: :openai,
        model: "gpt-4",
        result_formatter: :history_rag
      }

      context = %{
        existing_messages: [%{role: :user, content: "Hello"}]
      }

      request = LlmIntegration.create_llm_request(workflow_result, llm_config, context)

      assert request.invocation.provider == :openai
      assert request.invocation.model == "gpt-4"
      assert request.input.type == :chat
      assert is_list(request.input.messages)
    end

    test "handles different context integration types" do
      workflow_result = %{final_output: %{result: "test"}}

      llm_config = %{
        provider: :openai,
        model: "gpt-4",
        context_integration: :replace
      }

      request = LlmIntegration.create_llm_request(workflow_result, llm_config, %{})

      assert length(request.input.messages) == 1
      assert hd(request.input.messages).role == :user
    end
  end

  describe "configuration validation" do
    test "validates required fields" do
      valid_config = %{
        provider: :openai,
        model: "gpt-4"
      }

      assert :ok = LlmIntegration.validate_llm_config(valid_config)

      invalid_config = %{
        provider: :openai
        # missing model
      }

      assert {:error, _} = LlmIntegration.validate_llm_config(invalid_config)
    end

    test "validates formatter" do
      config_with_valid_formatter = %{
        provider: :openai,
        model: "gpt-4",
        result_formatter: :generic
      }

      assert :ok = LlmIntegration.validate_llm_config(config_with_valid_formatter)

      config_with_invalid_formatter = %{
        provider: :openai,
        model: "gpt-4",
        result_formatter: :nonexistent
      }

      assert {:error, _} = LlmIntegration.validate_llm_config(config_with_invalid_formatter)
    end

    test "validates provider config" do
      invalid_provider_config = %{
        provider: "not_an_atom",
        model: "gpt-4"
      }

      assert {:error, _} = LlmIntegration.validate_llm_config(invalid_provider_config)

      invalid_model_config = %{
        provider: :openai,
        model: 123
      }

      assert {:error, _} = LlmIntegration.validate_llm_config(invalid_model_config)
    end
  end

  describe "custom formatters" do
    test "registers and uses custom formatter" do
      formatter_name = :test_custom
      formatter_fn = fn result -> "Custom: #{inspect(result)}" end

      assert :ok = LlmIntegration.register_formatter(formatter_name, formatter_fn)
      assert formatter_name in LlmIntegration.list_formatters()

      workflow_result = %{final_output: %{test: "value"}}

      llm_config = %{
        provider: :openai,
        model: "gpt-4",
        result_formatter: formatter_name
      }

      formatted = LlmIntegration.format_for_llm(workflow_result, llm_config)
      assert String.starts_with?(formatted.content, "Custom:")
    end
  end

  describe "workflow context extraction" do
    test "extracts context from workflow result" do
      workflow_result = %{
        status: :ok,
        visited_nodes: [:start, :process, :end],
        final_output: %{result: "success"},
        trace: [
          %{node_id: :start, duration_ms: 10},
          %{node_id: :process, duration_ms: 50},
          %{node_id: :end, duration_ms: 5}
        ]
      }

      context = LlmIntegration.extract_workflow_context(workflow_result)

      assert context.workflow_status == :ok
      assert context.execution_path == [:start, :process, :end]
      assert context.performance_metrics.total_steps == 3
      assert context.performance_metrics.execution_time == 65
      assert context.error_context.has_error == false
    end

    test "extracts error context" do
      workflow_result = %{
        status: :error,
        error: "Something went wrong",
        visited_nodes: [:start],
        trace: []
      }

      context = LlmIntegration.extract_workflow_context(workflow_result)

      assert context.workflow_status == :error
      assert context.error_context.has_error == true
      assert context.error_context.error_details == "Something went wrong"
    end
  end
end
