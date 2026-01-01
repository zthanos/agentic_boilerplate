defmodule AgentCore.WorkflowEngine.HistoryWorkflow do
  @moduledoc """
  History RAG Augmentation workflow specification and utilities.

  This module defines the complete workflow specification for retrieving and
  composing historical context for message augmentation. It includes the
  workflow definition, predicate functions, and registration utilities.

  ## Workflow Flow

  1. **assess_need** - Evaluate if history is needed for the current message
  2. **build_query** - Generate search query from the message (if history needed)
  3. **retrieve_candidates** - Perform vector similarity search
  4. **rerank_candidates** - Optional reranking for improved relevance
  5. **compose_context** - Format selected candidates into context string
  6. **done** - Finalize workflow output

  ## Input/Output Contract

  - **Input**: `%{current_message: String.t(), conversation_id: String.t() | nil}`
  - **Output**: `%{history_context: String.t() | nil, history_items_used: integer()}`

  ## Usage

      # Register the workflow
      AgentCore.WorkflowEngine.HistoryWorkflow.register()

      # Run the workflow
      input = %{current_message: "What did we discuss about the project?", conversation_id: "conv_123"}
      {:ok, result} = AgentCore.WorkflowEngine.Runtime.run(:history_rag, input)
  """

  alias AgentCore.WorkflowEngine.{Spec, Registry}

  alias AgentCore.WorkflowEngine.HistoryWorkflow.{
    AssessNeedStep,
    BuildQueryStep,
    RetrieveCandidatesStep,
    RerankCandidatesStep,
    ComposeContextStep,
    DoneStep
  }

  @workflow_id :history_rag
  @workflow_version 1

  @doc """
  Returns the complete workflow specification for the History RAG workflow.

  ## Examples

      iex> spec = AgentCore.WorkflowEngine.HistoryWorkflow.spec()
      iex> spec.id
      :history_rag
      iex> spec.entry
      :assess_need
  """
  @spec spec() :: Spec.t()
  def spec do
    {:ok, spec} =
      Spec.new(
        id: @workflow_id,
        version: @workflow_version,
        entry: :assess_need,
        exits: [:done],
        nodes: %{
          assess_need: %{step: AssessNeedStep, opts: %{}},
          build_query: %{step: BuildQueryStep, opts: %{max_candidates: 10}},
          retrieve_candidates: %{step: RetrieveCandidatesStep, opts: %{}},
          rerank_candidates: %{step: RerankCandidatesStep, opts: %{max_results: 5}},
          compose_context: %{
            step: ComposeContextStep,
            opts: %{max_items: 5, include_timestamps: true}
          },
          done: %{step: DoneStep, opts: %{}}
        },
        edges: [
          # From assess_need: go to build_query if history needed, otherwise skip to done
          %{from: :assess_need, to: :build_query, when: {:decision, :needs_history, true}},
          %{from: :assess_need, to: :done, when: {:decision, :needs_history, false}},

          # From build_query: always go to retrieve_candidates
          %{
            from: :build_query,
            to: :retrieve_candidates,
            when: {:artifact_present, :history_query}
          },

          # From retrieve_candidates: go to rerank if we have candidates, otherwise compose with empty
          %{
            from: :retrieve_candidates,
            to: :rerank_candidates,
            when: {:custom, &candidates_not_empty/1}
          },
          %{
            from: :retrieve_candidates,
            to: :compose_context,
            when: {:custom, &candidates_empty/1}
          },

          # From rerank_candidates: always go to compose_context
          %{
            from: :rerank_candidates,
            to: :compose_context,
            when: {:artifact_present, :history_top}
          },

          # From compose_context: always go to done
          %{from: :compose_context, to: :done, when: {:always}}
        ],
        schema: %{
          input: %{
            type: :map,
            required: [:current_message],
            properties: %{
              current_message: %{type: :string},
              conversation_id: %{type: :string, nullable: true}
            }
          },
          output: %{
            type: :map,
            required: [:history_context, :history_items_used],
            properties: %{
              history_context: %{type: :string, nullable: true},
              history_items_used: %{type: :integer, minimum: 0}
            }
          }
        }
      )

    spec
  end

  @doc """
  Registers the History RAG workflow with the workflow registry.

  ## Examples

      iex> AgentCore.WorkflowEngine.HistoryWorkflow.register()
      :ok
  """
  @spec register() :: :ok | {:error, term()}
  def register do
    Registry.register_workflow(spec())
  end

  @doc """
  Predicate function to check if candidates are not empty.

  Used in workflow edges to determine routing based on whether
  candidates were retrieved.

  ## Examples

      iex> ctx = %{artifacts: %{history_candidates: [%{content: "test"}]}}
      iex> AgentCore.WorkflowEngine.HistoryWorkflow.candidates_not_empty(ctx)
      true

      iex> ctx = %{artifacts: %{history_candidates: []}}
      iex> AgentCore.WorkflowEngine.HistoryWorkflow.candidates_not_empty(ctx)
      false
  """
  @spec candidates_not_empty(map()) :: boolean()
  def candidates_not_empty(ctx) do
    candidates = get_in(ctx, [:artifacts, :history_candidates])
    is_list(candidates) and length(candidates) > 0
  end

  @doc """
  Predicate function to check if candidates are empty.

  Used in workflow edges to determine routing when no candidates
  were retrieved.

  ## Examples

      iex> ctx = %{artifacts: %{history_candidates: []}}
      iex> AgentCore.WorkflowEngine.HistoryWorkflow.candidates_empty(ctx)
      true

      iex> ctx = %{artifacts: %{history_candidates: [%{content: "test"}]}}
      iex> AgentCore.WorkflowEngine.HistoryWorkflow.candidates_empty(ctx)
      false
  """
  @spec candidates_empty(map()) :: boolean()
  def candidates_empty(ctx) do
    not candidates_not_empty(ctx)
  end

  @doc """
  Returns the workflow ID for the History RAG workflow.

  ## Examples

      iex> AgentCore.WorkflowEngine.HistoryWorkflow.workflow_id()
      :history_rag
  """
  @spec workflow_id() :: atom()
  def workflow_id, do: @workflow_id

  @doc """
  Returns the workflow version.

  ## Examples

      iex> AgentCore.WorkflowEngine.HistoryWorkflow.workflow_version()
      1
  """
  @spec workflow_version() :: integer()
  def workflow_version, do: @workflow_version
end
