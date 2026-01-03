#!/usr/bin/env elixir

# Simple script to create a test agent for the RAG conversation workflow

alias AgentCore.Llm.Agent.Definition, as: AgentDef
alias AgentWeb.Llm.AgentStoreEcto

# Create a simple test agent that uses the RAG conversation workflow
test_agent =
  AgentDef.new(%{
    id: "test_rag_agent",
    version: 1,
    name: "Test RAG Agent",
    description: "Simple test agent for RAG conversation workflow",
    metadata: %{
      "workflows" => ["rag_conversation"],
      "created_by" => "test_script",
      "created_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "purpose" => "testing"
    },
    profiles: %{
      "execution_profile_id" => "req_llm",
      "assessor_profile_id" => "req_llm"
    },
    prompts: %{
      "system" => "You are a helpful test assistant."
    },
    policies: %{}
  })

case AgentDef.validate(test_agent) do
  {:ok, validated_agent} ->
    case AgentStoreEcto.put(validated_agent) do
      {:ok, _} ->
        IO.puts("✅ Test agent created successfully: test_rag_agent")
      {:error, reason} ->
        IO.puts("❌ Failed to create test agent: #{inspect(reason)}")
    end
  {:error, errors} ->
    IO.puts("❌ Agent validation failed: #{inspect(errors)}")
end
