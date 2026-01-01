defmodule AgentCore.WorkflowEngine.AgentTest do
  use ExUnit.Case, async: true
  alias AgentCore.WorkflowEngine.Agent

  describe "agent creation and validation" do
    test "creates agent with valid configuration" do
      agent = Agent.new(%{
        id: "test_agent",
        workflows: [:test_workflow],
        default_workflow: :test_workflow
      })

      assert agent.id == "test_agent"
      assert agent.workflows == [:test_workflow]
      assert agent.default_workflow == :test_workflow
    end

    test "creates agent with LLM integration" do
      llm_config = %{
        provider: :openai,
        model: "gpt-4",
        result_formatter: :history_rag
      }

      agent = Agent.new(%{
        id: "llm_agent",
        workflows: [:history_rag],
        llm_integration: llm_config
      })

      assert agent.llm_integration == llm_config
      assert Agent.get_info(agent).has_llm_integration == true
    end

    test "validates required fields" do
      # Missing workflows
      assert {:error, "At least one workflow is required"} =
        Agent.validate(Agent.new(%{id: "test", workflows: []}))

      # Missing ID
      assert_raise KeyError, fn ->
        Agent.new(%{workflows: [:test]})
      end
    end

    test "can check workflow execution capability" do
      agent = Agent.new(%{
        id: "test_agent",
        workflows: [:workflow1, :workflow2]
      })

      assert Agent.can_execute_workflow?(agent, :workflow1) == true
      assert Agent.can_execute_workflow?(agent, :workflow2) == true
      assert Agent.can_execute_workflow?(agent, :workflow3) == false
    end

    test "lists available workflows" do
      workflows = [:workflow1, :workflow2, :workflow3]
      agent = Agent.new(%{
        id: "test_agent",
        workflows: workflows
      })

      assert Agent.list_workflows(agent) == workflows
    end

    test "adds routing rules" do
      agent = Agent.new(%{
        id: "test_agent",
        workflows: [:workflow1, :workflow2]
      })

      rule = %{
        condition: fn req -> req.input[:type] == "history" end,
        workflow_id: :workflow1
      }

      updated_agent = Agent.add_routing_rule(agent, rule)
      assert length(updated_agent.routing_rules) == 1
      assert hd(updated_agent.routing_rules) == rule
    end

    test "gets agent info" do
      agent = Agent.new(%{
        id: "test_agent",
        workflows: [:workflow1, :workflow2],
        default_workflow: :workflow1,
        metadata: %{version: "1.0"}
      })

      info = Agent.get_info(agent)

      assert info.id == "test_agent"
      assert info.workflows == [:workflow1, :workflow2]
      assert info.default_workflow == :workflow1
      assert info.has_llm_integration == false
      assert info.routing_rules_count == 0
      assert info.metadata == %{version: "1.0"}
    end
  end

  describe "LLM integration" do
    test "format_for_llm returns error when no LLM integration configured" do
      agent = Agent.new(%{
        id: "test_agent",
        workflows: [:test_workflow]
      })

      workflow_result = %{final_output: %{result: "test"}}

      assert {:error, "Agent does not have LLM integration configured"} =
        Agent.format_for_llm(agent, workflow_result)
    end

    test "create_llm_request returns error when no LLM integration configured" do
      agent = Agent.new(%{
        id: "test_agent",
        workflows: [:test_workflow]
      })

      workflow_result = %{final_output: %{result: "test"}}

      assert {:error, "Agent does not have LLM integration configured"} =
        Agent.create_llm_request(agent, workflow_result, %{})
    end

    test "format_for_llm works with valid LLM configuration" do
      llm_config = %{
        provider: :openai,
        model: "gpt-4",
        result_formatter: :generic
      }

      agent = Agent.new(%{
        id: "test_agent",
        workflows: [:test_workflow],
        llm_integration: llm_config
      })

      workflow_result = %{final_output: %{message: "Hello", count: 5}}

      assert {:ok, formatted} = Agent.format_for_llm(agent, workflow_result)
      assert formatted.integration_type == :generic
      assert is_binary(formatted.content)
      assert formatted.original_result == workflow_result
    end
  end
end
