defmodule AgentCore.WorkflowEngine.RagConversationWorkflow do
  @moduledoc """
  Comprehensive RAG-Enhanced Conversation Workflow Specification.

  This module defines the complete RAG-enhanced conversation workflow that intelligently
  augments user prompts with relevant historical context and handles clarification
  assessment. This workflow represents the primary conversation processing pipeline
  that transforms user messages into contextually enhanced prompts ready for LLM processing.

  ## Workflow Process

  The RAG-Enhanced Conversation workflow implements six steps for complete conversational AI processing:

  1. **LLM Query Generation**: Use LLM to analyze user message and generate structured queries
     for vector database retrieval of relevant historical context
  2. **Vector Database Retrieval**: Execute generated queries against conversation history
     to retrieve semantically similar content
  3. **Prompt Enhancement**: Augment original user prompt with retrieved historical context
     in structured format that preserves conversation flow
  4. **Clarification Assessment**: Evaluate enhanced prompt to determine if user clarification
     is needed before generating response
  5. **Response Routing**: Route to either clarification collection or direct LLM response generation
  6. **Final Processing**: Generate final response using enhanced context or collect user clarification

  ## Input/Output Contract

  - **Input**: `%{user_message: String.t(), conversation_id: String.t() | nil, user_context: map(), profile: map(), overrides: map()}`
  - **Output**: `%{enhanced_prompt: String.t(), needs_clarification: boolean(), clarification_questions: [String.t()] | nil, final_response: String.t() | nil}`

  ## Workflow Independence

  This workflow uses existing core infrastructure modules while maintaining workflow independence:
  - Uses core LLM executor infrastructure for consistent LLM interaction patterns
  - Uses existing vector database infrastructure with compatible query formats
  - Implements workflow-specific prompt formatting and clarification logic
  - Maintains independence from plan system clarification and error handling modules

  ## Registration

  The workflow is automatically registered with the WorkflowEngine.Registry when this module is loaded.
  All step modules are included in the registry's whitelist for security.
  """

  alias AgentCore.WorkflowEngine.{Spec, Registry}

  alias AgentCore.WorkflowEngine.RagConversationWorkflow.{
    GenerateQueryStep,
    RetrieveContextStep,
    EnhancePromptStep,
    AssessClarificationStep,
    FinalResponseStep,
    CollectClarificationStep
  }

  require Logger

  @workflow_id :rag_conversation
  @workflow_version 1

  @doc """
  Returns the complete RAG conversation workflow specification.

  This specification defines the comprehensive conversation processing pipeline
  with intelligent routing between response generation and clarification collection.

  ## Workflow Definition

  The workflow includes six nodes with sophisticated routing logic:

  - **generate_query**: Analyzes user message and generates structured queries for vector search
  - **retrieve_context**: Executes queries against conversation history vector database
  - **enhance_prompt**: Augments original prompt with retrieved historical context
  - **assess_clarification**: Evaluates enhanced prompt to determine clarification needs
  - **final_response**: Generates final LLM response when no clarification needed
  - **collect_clarification**: Handles clarification collection when additional info needed

  ## Edge Routing Logic

  The workflow uses sophisticated predicate functions for intelligent routing:

  1. From generate_query:
     - To retrieve_context if history_query artifact is present (LLM generated query)
     - To enhance_prompt if skip_history decision is true (no query needed)

  2. From retrieve_context:
     - To enhance_prompt when retrieved_context artifact is present

  3. From enhance_prompt:
     - To assess_clarification when enhanced_prompt artifact is present

  4. From assess_clarification:
     - To final_response if needs_clarification decision is false
     - To collect_clarification if needs_clarification decision is true

  Both final_response and collect_clarification are exit nodes, completing the workflow.

  ## Error Handling

  Each step implements comprehensive error handling with workflow-specific patterns:
  - LLM generation failures fall back to skipping history or using original prompts
  - Vector database errors result in empty context with graceful continuation
  - Clarification assessment errors default to no clarification needed
  - All errors are logged and captured in execution traces for observability
  """
  @spec get_workflow_spec() :: Spec.t()
  def get_workflow_spec do
    case Spec.new(
           id: @workflow_id,
           version: @workflow_version,
           entry: :generate_query,
           # Λίστα, όχι MapSet
           exits: [:final_response, :collect_clarification],
           nodes: %{
             generate_query: %{
               step: GenerateQueryStep,
               opts: %{
                 system_prompt: get_query_generation_system_prompt(),
                 max_query_length: 200,
                 fallback_behavior: :skip_history
               }
             },
             retrieve_context: %{
               step: RetrieveContextStep,
               opts: %{
                 limit: 10,
                 threshold: 0.7,
                 max_context_items: 5,
                 embeddings_profile_id: "embeddings_nomic_v15",
                 embeddings_profile_id_secondary: "embeddings_openai_v3"
               }
             },
             enhance_prompt: %{
               step: EnhancePromptStep,
               opts: %{
                 max_context_items: 5,
                 min_context_score: 0.3,
                 max_content_length: 500,
                 include_context_scores: false,
                 context_header: "Relevant conversation history:",
                 context_separator: "\n---\n"
               }
             },
             assess_clarification: %{
               step: AssessClarificationStep,
               opts: %{
                 system_prompt: get_clarification_assessment_system_prompt(),
                 assessment_temperature: 0.1,
                 max_questions: 3,
                 fallback_behavior: :no_clarification
               }
             },
             final_response: %{
               step: FinalResponseStep,
               opts: %{
                 system_prompt: get_response_generation_system_prompt(),
                 temperature: 0.7,
                 max_tokens: 2000,
                 request_timeout_ms: 15_000,
                 max_retries: 2,
                 max_response_length: 4000
               }
             },
             collect_clarification: %{
               step: CollectClarificationStep,
               opts: %{
                 regeneration_system_prompt: get_prompt_regeneration_system_prompt(),
                 regeneration_temperature: 0.3,
                 regeneration_max_tokens: 1500,
                 regeneration_timeout_ms: 10_000,
                 max_regenerated_prompt_length: 3000
               }
             }
           },
           edges: [
             # From generate_query: route based on query generation success
             %{
               from: :generate_query,
               to: :retrieve_context,
               when: {:artifact_present, :history_query}
             },
             %{
               from: :generate_query,
               to: :enhance_prompt,
               when: {:decision, :skip_history, true}
             },
             # From retrieve_context: always proceed to enhance_prompt
             %{
               from: :retrieve_context,
               to: :enhance_prompt,
               when: {:artifact_present, :retrieved_context}
             },
             # From enhance_prompt: always proceed to clarification assessment
             %{
               from: :enhance_prompt,
               to: :assess_clarification,
               when: {:artifact_present, :enhanced_prompt}
             },
             # From assess_clarification: route based on clarification need
             %{
               from: :assess_clarification,
               to: :final_response,
               when: {:decision, :needs_clarification, false}
             },
             %{
               from: :assess_clarification,
               to: :collect_clarification,
               when: {:decision, :needs_clarification, true}
             }
           ],
           schema: %{
             input: %{
               type: :map,
               required: [:user_message],
               properties: %{
                 user_message: %{type: :string, description: "The user's message to process"},
                 conversation_id: %{
                   type: :string,
                   description: "Optional conversation identifier for history retrieval"
                 },
                 user_context: %{
                   type: :map,
                   description: "Additional context about the user/conversation"
                 },
                 profile: %{type: :map, description: "LLM profile for execution"},
                 overrides: %{type: :map, description: "LLM overrides for execution"}
               }
             },
             output: %{
               type: :map,
               required: [:enhanced_prompt],
               properties: %{
                 enhanced_prompt: %{
                   type: :string,
                   description: "The final enhanced prompt with context"
                 },
                 needs_clarification: %{
                   type: :boolean,
                   description: "Whether clarification was needed"
                 },
                 clarification_questions: %{
                   type: :array,
                   description: "Questions asked for clarification"
                 },
                 final_response: %{
                   type: :string,
                   description: "Generated response if no clarification needed"
                 },
                 clarification_responses: %{
                   type: :array,
                   description: "User responses to clarification questions"
                 },
                 history_items_used: %{
                   type: :integer,
                   description: "Number of historical context items used"
                 },
                 generation_metadata: %{
                   type: :map,
                   description: "Metadata about response generation"
                 }
               }
             }
           }
         ) do
      {:ok, spec} ->
        spec

      {:error, errors} ->
        Logger.error("Failed to create workflow spec: #{inspect(errors)}")
        raise "Invalid workflow specification: #{inspect(errors)}"
    end
  end

  @doc """
  Registers the RAG conversation workflow with the WorkflowEngine.Registry.

  This function validates and registers the workflow specification, making it
  available for execution through the workflow engine. It includes comprehensive
  error handling and logging for registration failures.

  ## Returns

  - `:ok` if registration succeeds
  - `{:error, reason}` if registration fails

  ## Examples

      iex> AgentCore.WorkflowEngine.RagConversationWorkflow.register_workflow()
      :ok

      iex> # If workflow is already registered
      iex> AgentCore.WorkflowEngine.RagConversationWorkflow.register_workflow()
      :ok  # Registration is idempotent
  """
  @spec register_workflow() :: :ok | {:error, term()}
  def register_workflow do
    workflow_spec = get_workflow_spec()

    case Registry.register_workflow(workflow_spec) do
      :ok ->
        Logger.info(
          "[workflow] RAG conversation workflow registered successfully: #{@workflow_id}"
        )

        :ok

      {:error, reason} = error ->
        Logger.error(
          "[workflow] Failed to register RAG conversation workflow: #{inspect(reason)}"
        )

        error
    end
  end

  @doc """
  Validates the RAG conversation workflow specification without registering it.

  This function performs comprehensive validation of the workflow specification
  including node connectivity, edge validity, and predicate format validation.

  ## Returns

  - `:ok` if validation succeeds
  - `{:error, errors}` if validation fails with list of error details

  ## Examples

      iex> AgentCore.WorkflowEngine.RagConversationWorkflow.validate_workflow()
      :ok
  """
  @spec validate_workflow() :: :ok | {:error, [atom()]}
  def validate_workflow do
    workflow_spec = get_workflow_spec()
    Spec.validate(workflow_spec)
  end

  @doc """
  Returns the workflow ID for the RAG conversation workflow.
  """
  @spec workflow_id() :: atom()
  def workflow_id, do: @workflow_id

  @doc """
  Returns the workflow version for the RAG conversation workflow.
  """
  @spec workflow_version() :: integer()
  def workflow_version, do: @workflow_version

  # Private helper functions for system prompts

  # System prompt for query generation step
  defp get_query_generation_system_prompt do
    """
    You are an assistant that generates search queries for retrieving relevant conversation history.

    Given a user message, generate a concise search query that would help find relevant previous conversations or context.

    Guidelines:
    - Focus on the key concepts, topics, or entities mentioned
    - Use natural language that would match similar discussions
    - Keep queries concise but descriptive (3-50 words)
    - Avoid overly specific details that might miss relevant context
    - If the message is a greeting or doesn't need history, respond with an empty string

    Respond with ONLY the search query text, no additional formatting or explanation.

    Examples:
    User: "How did the deployment go yesterday?"
    Response: deployment status yesterday results

    User: "Can you continue working on the authentication feature?"
    Response: authentication feature development progress

    User: "Hello"
    Response:

    User: "What was the error we discussed about the database?"
    Response: database error discussion problem
    """
  end

  # System prompt for clarification assessment step
  defp get_clarification_assessment_system_prompt do
    """
    You are an assistant that analyzes enhanced prompts to determine if clarification is needed before generating responses.

    Your task is to evaluate whether the enhanced prompt (which includes the original user message plus retrieved historical context) provides sufficient clarity for generating a helpful response.

    Guidelines for assessment:
    - Consider if the user's intent is clear and unambiguous
    - Evaluate whether the enhanced context helps or creates confusion
    - Determine if additional information would significantly improve response quality
    - Look for conflicting information between the original message and context
    - Consider if the request is too vague or broad to address effectively

    Respond with a JSON object containing:
    {
      "needs_clarification": boolean,
      "reasoning": "brief explanation of your assessment",
      "questions": ["specific clarification question 1", "question 2", ...] (only if clarification needed)
    }

    If clarification is needed, provide 1-3 specific, actionable questions that would help clarify the user's intent.

    Examples of when clarification IS needed:
    - User asks "fix the bug" but context shows multiple different bugs discussed
    - Request is vague like "help me with this" without clear subject
    - Context contains conflicting information about user preferences
    - User refers to "that thing" without clear antecedent

    Examples of when clarification is NOT needed:
    - User request is specific and clear
    - Context provides helpful background without conflicts
    - Intent is obvious from the enhanced prompt
    - Request can be addressed effectively with available information
    """
  end

  # System prompt for response generation step
  defp get_response_generation_system_prompt do
    """
    You are a helpful AI assistant. You have been provided with a user message that may include relevant historical context from previous conversations.

    Please provide a helpful, accurate, and contextually appropriate response to the user's message. Use the historical context when relevant, but focus primarily on addressing the current user's needs.

    Guidelines:
    - Be helpful, accurate, and concise
    - Use historical context when it adds value to your response
    - If historical context seems irrelevant or conflicting, focus on the current message
    - Maintain a conversational and friendly tone
    - Provide actionable information when possible
    - If you're unsure about something, acknowledge the uncertainty

    Respond directly to the user's message using the provided context appropriately.
    """
  end

  # System prompt for prompt regeneration step
  defp get_prompt_regeneration_system_prompt do
    """
    You are an assistant that regenerates enhanced prompts by incorporating user clarification responses.

    Your task is to take an enhanced prompt (which includes original user message plus historical context) and improve it by incorporating clarification responses provided by the user.

    Guidelines for regeneration:
    - Maintain all relevant historical context from the original enhanced prompt
    - Incorporate clarification responses naturally and appropriately
    - Resolve ambiguities and unclear references using the clarification
    - Ensure the regenerated prompt provides clear direction for response generation
    - Keep the prompt focused and actionable
    - Preserve the original user's intent while adding clarity

    Process:
    1. Analyze the original enhanced prompt and identify areas that needed clarification
    2. Review the clarification Q&A pairs to understand user intent
    3. Integrate the clarification responses into the enhanced prompt
    4. Ensure the result is coherent and provides clear direction

    Return only the regenerated enhanced prompt without additional commentary, explanations, or formatting markers.
    """
  end
end
