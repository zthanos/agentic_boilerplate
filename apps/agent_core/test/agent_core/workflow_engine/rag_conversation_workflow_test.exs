defmodule AgentCore.WorkflowEngine.RagConversationWorkflowTest do
  use ExUnit.Case, async: true

  alias AgentCore.WorkflowEngine.RagConversationWorkflow
  alias AgentCore.WorkflowEngine.{Spec, Registry}

  @moduletag :workflow_engine

  describe "workflow specification" do
    test "get_workflow_spec/0 returns valid workflow specification" do
      spec = RagConversationWorkflow.get_workflow_spec()

      assert %Spec{} = spec
      assert spec.id == :rag_conversation
      assert spec.version == 1
      assert spec.entry == :generate_query
      assert MapSet.equal?(spec.exits, MapSet.new([:final_response, :collect_clarification]))

      # Verify all required nodes are present
      expected_nodes = [
        :generate_query,
        :retrieve_context,
        :enhance_prompt,
        :assess_clarification,
        :final_response,
        :collect_clarification
      ]

      for node <- expected_nodes do
        assert Map.has_key?(spec.nodes, node), "Missing node: #{node}"
      end

      # Verify edges are properly defined
      assert length(spec.edges) == 6

      # Verify schema is defined
      assert spec.schema != nil
      assert spec.schema.input != nil
      assert spec.schema.output != nil
    end

    test "validate_workflow/0 returns :ok for valid specification" do
      assert :ok = RagConversationWorkflow.validate_workflow()
    end

    test "workflow_id/0 returns correct ID" do
      assert RagConversationWorkflow.workflow_id() == :rag_conversation
    end

    test "workflow_version/0 returns correct version" do
      assert RagConversationWorkflow.workflow_version() == 1
    end
  end

  describe "workflow registration" do
    setup do
      # Clear registry before each test
      Registry.clear_workflows()
      :ok
    end

    test "register_workflow/0 successfully registers the workflow" do
      assert :ok = RagConversationWorkflow.register_workflow()

      # Verify workflow is registered
      assert {:ok, spec} = Registry.get_workflow(:rag_conversation)
      assert spec.id == :rag_conversation
    end

    test "register_workflow/0 is idempotent" do
      assert :ok = RagConversationWorkflow.register_workflow()
      assert :ok = RagConversationWorkflow.register_workflow()

      # Should still be registered
      assert {:ok, _spec} = Registry.get_workflow(:rag_conversation)
    end
  end

  describe "workflow edges and routing" do
    test "edges have correct routing logic" do
      spec = RagConversationWorkflow.get_workflow_spec()

      # Find specific edges and verify their predicates
      edges_by_from = Enum.group_by(spec.edges, & &1.from)

      # From generate_query
      generate_query_edges = edges_by_from[:generate_query]
      assert length(generate_query_edges) == 2

      # Should route to retrieve_context when history_query artifact is present
      retrieve_edge = Enum.find(generate_query_edges, &(&1.to == :retrieve_context))
      assert retrieve_edge.when == {:artifact_present, :history_query}

      # Should route to enhance_prompt when skip_history decision is true
      skip_edge = Enum.find(generate_query_edges, &(&1.to == :enhance_prompt))
      assert skip_edge.when == {:decision, :skip_history, true}

      # From assess_clarification
      assess_edges = edges_by_from[:assess_clarification]
      assert length(assess_edges) == 2

      # Should route to final_response when no clarification needed
      final_edge = Enum.find(assess_edges, &(&1.to == :final_response))
      assert final_edge.when == {:decision, :needs_clarification, false}

      # Should route to collect_clarification when clarification needed
      clarify_edge = Enum.find(assess_edges, &(&1.to == :collect_clarification))
      assert clarify_edge.when == {:decision, :needs_clarification, true}
    end
  end

  describe "step module configuration" do
    test "all step modules are properly configured with options" do
      spec = RagConversationWorkflow.get_workflow_spec()

      # Verify each node has proper step module and options
      for {node_id, node_config} <- spec.nodes do
        assert Map.has_key?(node_config, :step), "Node #{node_id} missing step module"
        assert Map.has_key?(node_config, :opts), "Node #{node_id} missing options"
        assert is_atom(node_config.step), "Node #{node_id} step should be module atom"
        assert is_map(node_config.opts), "Node #{node_id} opts should be map"
      end

      # Verify specific step modules
      assert spec.nodes[:generate_query].step ==
               AgentCore.WorkflowEngine.RagConversationWorkflow.GenerateQueryStep

      assert spec.nodes[:retrieve_context].step ==
               AgentCore.WorkflowEngine.RagConversationWorkflow.RetrieveContextStep

      assert spec.nodes[:enhance_prompt].step ==
               AgentCore.WorkflowEngine.RagConversationWorkflow.EnhancePromptStep

      assert spec.nodes[:assess_clarification].step ==
               AgentCore.WorkflowEngine.RagConversationWorkflow.AssessClarificationStep

      assert spec.nodes[:final_response].step ==
               AgentCore.WorkflowEngine.RagConversationWorkflow.FinalResponseStep

      assert spec.nodes[:collect_clarification].step ==
               AgentCore.WorkflowEngine.RagConversationWorkflow.CollectClarificationStep
    end

    test "step options contain expected configuration" do
      spec = RagConversationWorkflow.get_workflow_spec()

      # Verify generate_query options
      generate_opts = spec.nodes[:generate_query].opts
      assert Map.has_key?(generate_opts, :system_prompt)
      assert Map.has_key?(generate_opts, :max_query_length)

      # Verify retrieve_context options
      retrieve_opts = spec.nodes[:retrieve_context].opts
      assert Map.has_key?(retrieve_opts, :limit)
      assert Map.has_key?(retrieve_opts, :threshold)

      # Verify enhance_prompt options
      enhance_opts = spec.nodes[:enhance_prompt].opts
      assert Map.has_key?(enhance_opts, :max_context_items)
      assert Map.has_key?(enhance_opts, :context_header)

      # Verify assess_clarification options
      assess_opts = spec.nodes[:assess_clarification].opts
      assert Map.has_key?(assess_opts, :system_prompt)
      assert Map.has_key?(assess_opts, :max_questions)

      # Verify final_response options
      final_opts = spec.nodes[:final_response].opts
      assert Map.has_key?(final_opts, :temperature)
      assert Map.has_key?(final_opts, :max_tokens)

      # Verify collect_clarification options
      collect_opts = spec.nodes[:collect_clarification].opts
      assert Map.has_key?(collect_opts, :regeneration_system_prompt)
      assert Map.has_key?(collect_opts, :regeneration_temperature)
    end
  end

  describe "input/output schema" do
    test "input schema defines required fields" do
      spec = RagConversationWorkflow.get_workflow_spec()

      input_schema = spec.schema.input
      assert input_schema.type == :map
      assert :user_message in input_schema.required

      # Verify properties are defined
      assert Map.has_key?(input_schema.properties, :user_message)
      assert Map.has_key?(input_schema.properties, :conversation_id)
      assert Map.has_key?(input_schema.properties, :profile)
    end

    test "output schema defines expected fields" do
      spec = RagConversationWorkflow.get_workflow_spec()

      output_schema = spec.schema.output
      assert output_schema.type == :map
      assert :enhanced_prompt in output_schema.required

      # Verify properties are defined
      assert Map.has_key?(output_schema.properties, :enhanced_prompt)
      assert Map.has_key?(output_schema.properties, :needs_clarification)
      assert Map.has_key?(output_schema.properties, :final_response)
    end
  end
end
