defmodule AgentCore.WorkflowEngine.RagConversationWorkflow.AssessClarificationStep do
  @moduledoc """
  Step to assess whether clarification is needed for enhanced prompts using LLM analysis.

  This step evaluates enhanced prompts to determine if additional user clarification
  is required before proceeding with response generation. It uses LLM to analyze
  the prompt content and context to make intelligent routing decisions between
  direct response generation and clarification collection.

  ## Input

  Expects:
  - `ctx.artifacts[:enhanced_prompt]` - The enhanced prompt from previous step
  - `user_message` from workflow input - The original user message
  - `profile` - LLM profile for clarification assessment
  - `overrides` - LLM overrides for execution

  ## Output

  Sets `ctx.decisions[:needs_clarification]` to true/false and optionally
  `ctx.artifacts[:clarification_questions]` with generated questions.

  ## Clarification Assessment Logic

  Uses LLM to analyze the enhanced prompt and determine if:
  - The prompt is ambiguous or unclear
  - Additional context would improve response quality
  - User intent needs clarification
  - The enhanced context creates confusion

  ## Workflow Independence

  This implementation is workflow-specific and independent of plan system
  clarification modules. It uses core LLM infrastructure but maintains
  its own assessment logic and error handling patterns.
  """

  @behaviour AgentCore.WorkflowEngine.Step

  require Logger
  alias AgentCore.Providers.Response

  @impl true
  def id, do: :assess_clarification

  @impl true
  def run(ctx, input, opts) do
    enhanced_prompt = AgentCore.WorkflowEngine.Context.get_artifact(ctx, :enhanced_prompt)
    user_message = Map.get(input, :user_message, "")
    profile = Map.get(input, :profile)
    overrides = Map.get(input, :overrides, %{})

    # Normalize user_message to handle nil values
    normalized_user_message = if is_binary(user_message), do: user_message, else: ""

    case assess_clarification_need(
           enhanced_prompt,
           normalized_user_message,
           profile,
           overrides,
           opts
         ) do
      {:ok, needs_clarification, clarification_data} ->
        updated_ctx =
          ctx
          |> AgentCore.WorkflowEngine.Context.put_decision(
            :needs_clarification,
            needs_clarification
          )

        # Add clarification questions if they exist
        updated_ctx =
          if Map.has_key?(clarification_data, :questions) do
            AgentCore.WorkflowEngine.Context.put_artifact(
              updated_ctx,
              :clarification_questions,
              clarification_data.questions
            )
          else
            updated_ctx
          end

        output = %{
          needs_clarification: needs_clarification,
          assessment_completed: true,
          enhanced_prompt_length: String.length(enhanced_prompt || ""),
          original_message_length: String.length(normalized_user_message),
          clarification_data: clarification_data
        }

        {:ok, updated_ctx, output}

      {:error, reason} ->
        Logger.warning("[workflow] assess_clarification failed: #{inspect(reason)}")

        # Default to no clarification needed on error
        updated_ctx =
          AgentCore.WorkflowEngine.Context.put_decision(ctx, :needs_clarification, false)

        output = %{
          needs_clarification: false,
          assessment_completed: false,
          error: reason,
          fallback_used: true,
          enhanced_prompt_length: String.length(enhanced_prompt || ""),
          original_message_length: String.length(normalized_user_message)
        }

        {:ok, updated_ctx, output}
    end
  end

  # Assess clarification need using LLM analysis
  defp assess_clarification_need(enhanced_prompt, user_message, profile, overrides, opts)
       when not is_nil(profile) do
    # Skip assessment if no enhanced prompt
    if is_nil(enhanced_prompt) or String.trim(enhanced_prompt) == "" do
      {:ok, false, %{reason: "no_enhanced_prompt"}}
    else
      # Get system prompt from options or use default
      system_prompt = get_system_prompt(opts)

      # Build LLM input for clarification assessment
      llm_input = %{
        type: :chat,
        messages: [
          %{role: :system, content: system_prompt},
          %{role: :user, content: build_assessment_prompt(enhanced_prompt, user_message)}
        ]
      }

      # Build execution metadata
      exec_meta = %{
        "phase" => "assess_clarification_need"
      }

      # Execute LLM request with appropriate overrides
      assessment_overrides =
        Map.merge(
          %{
            "generation" => %{"temperature" => 0.1},
            "budgets" => %{"request_timeout_ms" => 8_000, "max_retries" => 1}
          },
          overrides
        )

      case AgentRuntime.Llm.Executor.execute(profile, assessment_overrides, llm_input, exec_meta) do
        {:ok, %{response: response}} ->
          case Response.content(response) do
            text when is_binary(text) and text != "" ->
              parse_clarification_response(text)

            _ ->
              {:error, "invalid_response_format"}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp assess_clarification_need(_enhanced_prompt, _user_message, _profile, _overrides, _opts) do
    {:error, "no_profile"}
  end

  # Build the assessment prompt for LLM analysis
  defp build_assessment_prompt(enhanced_prompt, user_message) do
    """
    Please analyze the following enhanced prompt to determine if clarification is needed before generating a response.

    Original user message:
    #{user_message}

    Enhanced prompt with context:
    #{enhanced_prompt}

    Consider whether:
    1. The user's intent is clear and unambiguous
    2. The enhanced context provides sufficient information
    3. There are conflicting or confusing elements
    4. Additional clarification would improve response quality

    If clarification is needed, suggest 1-3 specific questions that would help clarify the user's intent.
    """
  end

  # Parse LLM response to extract clarification assessment
  defp parse_clarification_response(text) do
    try do
      # Try to parse as JSON first
      case Jason.decode(text) do
        {:ok, parsed} when is_map(parsed) ->
          parse_structured_response(parsed)

        {:error, _} ->
          # If not JSON, try to parse as plain text
          parse_text_response(text)
      end
    rescue
      _ ->
        parse_text_response(text)
    end
  end

  # Parse structured JSON response
  defp parse_structured_response(parsed) do
    needs_clarification =
      extract_boolean_value(parsed, [
        "needs_clarification",
        "clarification_needed",
        "needs_clarity"
      ])

    questions = extract_questions(parsed)

    clarification_data = %{
      reasoning: Map.get(parsed, "reasoning") || Map.get(parsed, "reason"),
      confidence: Map.get(parsed, "confidence"),
      questions: questions
    }

    {:ok, needs_clarification, clarification_data}
  end

  # Parse plain text response
  defp parse_text_response(text) do
    text_lower = String.downcase(text)

    # Look for indicators of clarification need
    clarification_indicators = [
      "clarification needed",
      "needs clarification",
      "clarification required",
      "unclear",
      "ambiguous",
      "confusing",
      "more information needed"
    ]

    no_clarification_indicators = [
      "no clarification needed",
      "clear",
      "sufficient",
      "unambiguous",
      "ready to respond"
    ]

    needs_clarification =
      cond do
        Enum.any?(no_clarification_indicators, &String.contains?(text_lower, &1)) ->
          false

        Enum.any?(clarification_indicators, &String.contains?(text_lower, &1)) ->
          true

        true ->
          # Default to false if unclear
          false
      end

    # Try to extract questions from text
    questions = extract_questions_from_text(text)

    clarification_data = %{
      reasoning: "parsed_from_text",
      questions: questions,
      raw_response: String.slice(text, 0, 200)
    }

    {:ok, needs_clarification, clarification_data}
  end

  # Extract boolean value from various possible keys
  defp extract_boolean_value(parsed, keys) do
    Enum.find_value(keys, false, fn key ->
      case Map.get(parsed, key) do
        true -> true
        false -> false
        "true" -> true
        "false" -> false
        "yes" -> true
        "no" -> false
        1 -> true
        0 -> false
        _ -> nil
      end
    end)
  end

  # Extract questions from parsed response
  defp extract_questions(parsed) when is_map(parsed) do
    # Try various possible keys for questions
    question_keys = ["questions", "clarification_questions", "suggested_questions", "question"]

    Enum.find_value(question_keys, [], fn key ->
      case Map.get(parsed, key) do
        questions when is_list(questions) ->
          questions
          |> Enum.filter(&is_binary/1)
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        question when is_binary(question) and question != "" ->
          [String.trim(question)]

        _ ->
          nil
      end
    end) || []
  end

  # Extract questions from plain text
  defp extract_questions_from_text(text) do
    # Look for lines that end with question marks
    text
    |> String.split(["\n", "\r\n"])
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&String.ends_with?(&1, "?"))
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    # Limit to 3 questions max
    |> Enum.take(3)
  end

  # Get system prompt for clarification assessment
  defp get_system_prompt(opts) do
    Map.get(opts, :system_prompt, default_system_prompt())
  end

  # Default system prompt for clarification assessment
  defp default_system_prompt do
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
end
