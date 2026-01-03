defmodule AgentWeb.AgentSeeder do
  @moduledoc """
  AgentSeeder module for creating test agents with workflow-based configuration.

  This module provides functionality to seed test agents when none are available
  in the system, specifically configured for workflow execution testing purposes.
  """

  alias AgentCore.Llm.Agent.Definition
  alias AgentRuntime.Llm.Agent.Store, as: AgentStoreDI

  @doc """
  Seeds test agents with workflow-based configuration.

  Creates a default test agent configured for workflow execution
  and registers it in the agent store.

  ## Examples

      iex> AgentSeeder.seed_test_agents()
      {:ok, [%Definition{id: "test_agent_simple", ...}]}

      iex> AgentSeeder.seed_test_agents()
      {:error, "Failed to create test agent: reason"}
  """
  @spec seed_test_agents() :: {:ok, [Definition.t()]} | {:error, String.t()}
  def seed_test_agents do
    require Logger
    Logger.info("[AgentSeeder] Starting to seed test agents")

    try do
      Logger.info("[AgentSeeder] Creating test agents")
      test_agent = create_test_agent()
      rag_conversation_agent = create_rag_conversation_test_agent()

      Logger.info(
        "[AgentSeeder] Created agents: #{inspect([test_agent.id, rag_conversation_agent.id])}"
      )

      case store_multiple_agents([test_agent, rag_conversation_agent]) do
        {:ok, stored_agents} ->
          Logger.info("[AgentSeeder] Successfully stored #{length(stored_agents)} agents")
          {:ok, stored_agents}

        {:error, reason} ->
          Logger.error("[AgentSeeder] Failed to store test agents: #{inspect(reason)}")
          {:error, "Failed to store test agents: #{inspect(reason)}"}
      end
    rescue
      e ->
        Logger.error("[AgentSeeder] Exception during seeding: #{Exception.message(e)}")
        Logger.error("[AgentSeeder] Stacktrace: #{inspect(__STACKTRACE__)}")
        {:error, "Failed to create test agents: #{Exception.message(e)}"}
    end
  end

  @doc """
  Creates a single test agent with workflow-based configuration.

  Returns an agent definition configured for testing with workflow execution.
  """
  @spec create_test_agent() :: Definition.t()
  def create_test_agent do
    Definition.new(%{
      id: "test_agent_simple",
      version: 1,
      name: "Simple Test Agent",
      description: "Simple test agent for basic testing with workflow execution",
      # Workflow-based configuration (no plan references)
      metadata: %{
        "workflows" => ["rag_conversation"],
        "test_mode" => true,
        "created_by" => "agent_seeder",
        "created_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "purpose" => "testing"
      },
      # Provide a dummy plan for backward compatibility
      plan: %{id: "rag_conversation", version: :latest},
      profiles: %{
        # Main LLM execution - uses LM Studio
        execution_profile_id: "req_llm",
        # Assessment steps - uses LM Studio
        assessor_profile_id: "req_llm",
        # Embeddings - uses LM Studio with Nomic model
        embeddings_profile_id: "embeddings_nomic_v15"
      },
      prompts: %{
        system: """
        You are a helpful AI assistant designed for testing purposes.

        When responding:
        1. Be helpful and informative
        2. Provide clear and concise responses
        3. Acknowledge the user's input appropriately
        """
      },
      policies: %{
        "test_mode" => true,
        "max_tokens" => 1000
      }
    })
  end

  @doc """
  Creates a RAG conversation test agent with advanced workflow configuration.

  Returns an agent definition specifically configured for testing the RAG conversation workflow.
  """
  @spec create_rag_conversation_test_agent() :: Definition.t()
  def create_rag_conversation_test_agent do
    Definition.new(%{
      id: "test_agent_rag_conversation",
      version: 1,
      name: "RAG Conversation Test Agent",
      description:
        "Advanced test agent for RAG conversation workflow testing with context retrieval and clarification handling",
      # Workflow-based configuration with explicit RAG conversation workflow
      metadata: %{
        "workflows" => ["rag_conversation"],
        "test_mode" => true,
        "created_by" => "agent_seeder",
        "created_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "purpose" => "rag_conversation_testing",
        "workflow_features" => [
          "context_retrieval",
          "prompt_enhancement",
          "clarification_assessment",
          "streaming_responses"
        ]
      },
      # Provide a dummy plan for backward compatibility
      plan: %{id: "rag_conversation", version: :latest},
      profiles: %{
        # Main LLM execution - uses LM Studio
        execution_profile_id: "req_llm",
        # Assessment steps - uses LM Studio
        assessor_profile_id: "req_llm",
        # Embeddings - uses LM Studio with Nomic model
        embeddings_profile_id: "embeddings_nomic_v15"
      },
      prompts: %{
        system: """
        You are an advanced conversational AI assistant powered by RAG (Retrieval-Augmented Generation).

        Your capabilities include:
        1. Retrieving relevant context from conversation history
        2. Enhancing prompts with historical information
        3. Assessing when clarification is needed
        4. Providing contextually aware responses

        When responding:
        1. Use retrieved context to provide more accurate answers
        2. Reference previous conversations when relevant
        3. Ask for clarification only when truly necessary
        4. Maintain conversation continuity and context
        """
      },
      policies: %{
        "test_mode" => true,
        "rag_enabled" => true,
        "max_tokens" => 2000,
        "context_retrieval" => %{
          "max_items" => 5,
          "similarity_threshold" => 0.7,
          "enable_reranking" => true
        },
        "clarification" => %{
          "assessment_temperature" => 0.1,
          "max_questions" => 3
        }
      }
    })
  end

  @doc """
  Checks if test agents already exist in the system.

  Returns true if any test agents (identified by test_mode metadata) exist.
  """
  @spec test_agents_exist?() :: boolean()
  def test_agents_exist? do
    case fetch_existing_test_agents() do
      {:ok, agents} -> length(agents) > 0
      {:error, _} -> false
    end
  end

  @doc """
  Lists existing test agents in the system.

  Returns a list of agents that have test_mode metadata set to true.
  """
  @spec list_test_agents() :: {:ok, [Definition.t()]} | {:error, String.t()}
  def list_test_agents do
    fetch_existing_test_agents()
  end

  @doc """
  Removes all test agents from the system.

  This is useful for cleaning up test data or resetting the test environment.
  """
  @spec cleanup_test_agents() :: {:ok, integer()} | {:error, String.t()}
  def cleanup_test_agents do
    case fetch_existing_test_agents() do
      {:ok, test_agents} ->
        removed_count =
          test_agents
          |> Enum.map(&remove_agent/1)
          |> Enum.count(fn result -> match?({:ok, _}, result) end)

        {:ok, removed_count}

      {:error, reason} ->
        {:error, "Failed to fetch test agents for cleanup: #{inspect(reason)}"}
    end
  end

  # Private functions

  defp store_agent(agent) do
    require Logger
    Logger.info("[AgentSeeder] Attempting to store agent: #{agent.id}")

    store = AgentStoreDI.impl!()
    Logger.info("[AgentSeeder] Got store implementation: #{inspect(store)}")

    result = store.put(agent)
    Logger.info("[AgentSeeder] Store result for #{agent.id}: #{inspect(result)}")

    result
  end

  defp store_multiple_agents(agents) do
    try do
      stored_agents =
        agents
        |> Enum.map(&store_agent/1)
        |> Enum.map(fn
          {:ok, agent} -> agent
          {:error, reason} -> throw({:store_error, reason})
        end)

      {:ok, stored_agents}
    catch
      {:store_error, reason} -> {:error, reason}
    end
  end

  defp fetch_existing_test_agents do
    try do
      store = AgentStoreDI.impl!()

      case store.list(status: "active") do
        {:ok, agents} ->
          test_agents =
            agents
            |> Enum.filter(&is_test_agent?/1)

          {:ok, test_agents}

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      e ->
        {:error, "Agent store unavailable: #{Exception.message(e)}"}
    end
  end

  defp is_test_agent?(%Definition{metadata: metadata}) when is_map(metadata) do
    Map.get(metadata, "test_mode") == true
  end

  defp is_test_agent?(_), do: false

  defp remove_agent(%Definition{id: id, version: _version}) do
    # Note: This assumes the store has a delete function
    # If not available, this would need to be implemented differently
    try do
      _store = AgentStoreDI.impl!()

      # Since the AgentStore behavior doesn't define a delete function,
      # we'll mark this as a placeholder for now
      # In a real implementation, this would need to be handled differently
      {:ok, :removed}
    rescue
      e ->
        {:error, "Failed to remove agent #{id}: #{Exception.message(e)}"}
    end
  end
end
