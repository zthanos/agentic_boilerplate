defmodule AgentRuntime.Llm.Plan.Steps.AssessNeedForHistoryStep do
  @behaviour AgentRuntime.Llm.Plan.Step
  require Logger

  alias AgentRuntime.Llm.Plan.PlanContext
  alias AgentRuntime.Llm.Plan.StepUtils
  alias AgentRuntime.Llm.Executor

  @impl true
  def name, do: "assess_need_for_history"

  @impl true
  def run(%PlanContext{} = ctx, opts) do
    assessor_profile = resolve_assessor_profile(ctx, opts)

    overrides =
      Keyword.get(opts, :assessor_overrides, %{
        "generation" => %{"temperature" => 0},
        "budgets" => %{"request_timeout_ms" => 8_000, "max_retries" => 0}
      })

    user_prompt = StepUtils.last_user_prompt(ctx)

    cond do
      is_nil(user_prompt) or String.trim(user_prompt) == "" ->
        ctx =
          ctx
          |> PlanContext.put_decision(:history_query, nil)
          |> PlanContext.add_debug(name(), %{
            "skipped" => true,
            "reason" => "missing_or_blank_user_prompt"
          })

        {:cont, ctx}

      is_nil(assessor_profile) ->
        ctx =
          ctx
          |> PlanContext.put_decision(:history_query, nil)
          |> PlanContext.add_debug(name(), %{
            "skipped" => true,
            "reason" => "assessor_profile_missing_or_invalid"
          })

        {:cont, ctx}

      true ->
        system_prompt = build_system_prompt()

        llm_input = %{
          type: :chat,
          messages: [
            %{role: :system, content: system_prompt},
            %{role: :user, content: user_prompt}
          ]
        }

        # Execute with current phase from exec_meta (will be "assess_history")
        case Executor.execute(assessor_profile, overrides, llm_input, ctx.exec_meta) do
          {:ok, %{response: %{output_text: text}, run_id: run_id}} ->
            Logger.info("[plan] assess_history raw LLM output: #{inspect(text)}")

            result_map =
              text
              |> StepUtils.safe_json_decode()

            query = StepUtils.string_or_nil(result_map, "query")
            Logger.info("[plan] assess_history parsed query: #{inspect(query)}")

            # ... rest of the code ...

            ctx =
              ctx
              |> PlanContext.put_decision(:history_query, query)
              |> PlanContext.add_debug(name(), %{
                "query" => query,
                "run_id" => run_id
              })

            Logger.info("[plan] assess_history completed: query=#{inspect(query)} run_id=#{run_id}")
            {:cont, ctx}

          {:error, %{reason: reason, run_id: run_id}} ->
            ctx =
              ctx
              |> PlanContext.put_decision(:history_query, nil)
              |> PlanContext.add_debug(name(), %{
                "assess_error" => inspect(reason),
                "run_id" => run_id
              })

            Logger.warning("[plan] assess_history error: #{inspect(reason)}")
            {:cont, ctx}

          other ->
            ctx = PlanContext.add_debug(ctx, name(), %{"assess_unexpected" => inspect(other)})
            Logger.warning("[plan] assess_history unexpected: #{inspect(other)}")
            {:cont, ctx}
        end
    end
  end

  defp resolve_assessor_profile(%PlanContext{} = ctx, opts) do
    case Keyword.get(opts, :assessor_profile) do
      p when is_map(p) ->
        p

      _ ->
        p2 = Map.get(ctx, :profile)
        if is_map(p2), do: p2, else: nil
    end
  end

  defp build_system_prompt do
    """
    Analyze if this user message needs historical context from the conversation.

    IMPORTANT: This conversation already has history. Previous messages exist in the database.
    Your job is to decide what search query to use to retrieve that history.

    Return ONLY valid JSON:
    {
      "query": string | null
    }

    Decision rules:
    1. If the message is a greeting or introduction (first message) → null
    2. If the message asks about or references something previously discussed → MUST return query
    3. If the message continues a topic, asks follow-up questions → MUST return query
    4. If unsure, return a query (better to have context than miss it)
    5. Only return null for completely standalone, context-free messages

    Query guidelines:
    - Extract key nouns, entities, topics
    - 3-8 words max
    - No quotes, just plain text
    - Focus on what would match in vector search

    Examples:
    Input: "What's my job?"
    Output: {"query": "user's job occupation"}

    Input: "Tell me about yourself"
    Output: {"query": "assistant introduction description"}

    Input: "Hello"
    Output: {"query": null}
    """
  end

end
