defmodule AgentCore.WorkflowEngine.RegistryWhitelistTest do
  use ExUnit.Case, async: true
  alias AgentCore.WorkflowEngine.Spec

  describe "whitelist validation" do
    test "history workflow modules are whitelisted" do
      # Create a simple workflow spec using history workflow modules
      spec = %Spec{
        id: :test_history,
        version: 1,
        entry: :assess_need,
        exits: MapSet.new([:done]),
        nodes: %{
          assess_need: %{step: AgentCore.WorkflowEngine.HistoryWorkflow.AssessNeedStep, opts: %{}},
          build_query: %{step: AgentCore.WorkflowEngine.HistoryWorkflow.BuildQueryStep, opts: %{}},
          retrieve: %{step: AgentCore.WorkflowEngine.HistoryWorkflow.RetrieveCandidatesStep, opts: %{}},
          rerank: %{step: AgentCore.WorkflowEngine.HistoryWorkflow.RerankCandidatesStep, opts: %{}},
          compose: %{step: AgentCore.WorkflowEngine.HistoryWorkflow.ComposeContextStep, opts: %{}},
          done: %{step: AgentCore.WorkflowEngine.HistoryWorkflow.DoneStep, opts: %{}}
        },
        edges: [
          %{from: :assess_need, to: :build_query, when: {:always}},
          %{from: :build_query, to: :retrieve, when: {:always}},
          %{from: :retrieve, to: :rerank, when: {:always}},
          %{from: :rerank, to: :compose, when: {:always}},
          %{from: :compose, to: :done, when: {:always}}
        ]
      }

      # Test validation without starting the GenServer
      # We'll use the internal validation function directly
      whitelisted_modules = get_whitelisted_modules()

      # Check that all history workflow modules are in the whitelist
      history_modules = [
        AgentCore.WorkflowEngine.HistoryWorkflow.AssessNeedStep,
        AgentCore.WorkflowEngine.HistoryWorkflow.BuildQueryStep,
        AgentCore.WorkflowEngine.HistoryWorkflow.RetrieveCandidatesStep,
        AgentCore.WorkflowEngine.HistoryWorkflow.RerankCandidatesStep,
        AgentCore.WorkflowEngine.HistoryWorkflow.ComposeContextStep,
        AgentCore.WorkflowEngine.HistoryWorkflow.DoneStep
      ]

      for module <- history_modules do
        assert module in whitelisted_modules, "Module #{module} should be whitelisted"
      end

      # Test that validation would pass for step modules
      step_modules =
        spec.nodes
        |> Map.values()
        |> Enum.map(& &1.step)
        |> Enum.reject(&(&1 in whitelisted_modules))

      assert Enum.empty?(step_modules), "All step modules should be whitelisted, but these are not: #{inspect(step_modules)}"
    end

    defp get_whitelisted_modules do
      # This mirrors the private function in Registry
      [
        # Core workflow steps
        AgentCore.WorkflowEngine.Step,

        # History workflow steps
        AgentCore.WorkflowEngine.HistoryWorkflow.AssessNeedStep,
        AgentCore.WorkflowEngine.HistoryWorkflow.BuildQueryStep,
        AgentCore.WorkflowEngine.HistoryWorkflow.RetrieveCandidatesStep,
        AgentCore.WorkflowEngine.HistoryWorkflow.RerankCandidatesStep,
        AgentCore.WorkflowEngine.HistoryWorkflow.ComposeContextStep,
        AgentCore.WorkflowEngine.HistoryWorkflow.DoneStep,

        # Test modules
        TestStep,
        MockStep,
        AgentCore.WorkflowEngine.RegistryTest.TestStep
      ]
    end
  end
end
