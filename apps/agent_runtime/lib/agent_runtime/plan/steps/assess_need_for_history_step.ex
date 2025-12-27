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
    overrides = Keyword.get(opts, :assessor_overrides, %{
      "generation" => %{"temperature" => 0},
      "budgets" => %{"request_timeout_ms" => 8_000, "max_retries" => 0}
    })

    if is_nil(assessor_profile) do
      ctx =
        ctx
        |> PlanContext.put_decision(:needs_history, false)
        |> PlanContext.put_decision(:history_query, nil)
        |> PlanContext.add_debug(name(), %{
          "skipped" => true,
          "reason" => "assessor_profile_missing_or_invalid"
        })

      {:cont, ctx}
    else
      user_prompt = StepUtils.last_user_prompt(ctx)
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
          result_map =
            text
            |> StepUtils.safe_json_decode()
            |> StepUtils.enforce_null_when_false("needs_history", "query")

          needs = StepUtils.boolean(result_map, "needs_history", false)
          query = StepUtils.string_or_nil(result_map, "query")

          ctx =
            ctx
            |> PlanContext.put_decision(:needs_history, needs)
            |> PlanContext.put_decision(:history_query, query)
            |> PlanContext.add_debug(name(), %{
              "needs_history" => needs,
              "query" => query,
              "run_id" => run_id  # Store run_id for parent linking
            })

          Logger.info("[plan] assess_history completed: needs=#{needs} run_id=#{run_id}")
          {:cont, ctx}

        {:error, %{reason: reason, run_id: run_id}} ->
          ctx =
            ctx
            |> PlanContext.put_decision(:needs_history, false)
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
      p when is_map(p) -> p
      _ ->
        p2 = Map.get(ctx, :profile)
        if is_map(p2), do: p2, else: nil
    end
  end

  defp build_system_prompt do
    """
    You are deciding whether previous conversation history is needed to answer the user's request.

    Return ONLY valid JSON.

    Schema:
    {
      "needs_history": boolean,
      "query": string | null
    }

    Rules:
    - If the request references earlier context, previous answers, decisions, or "as discussed before" -> needs_history = true
    - If needs_history = false -> query MUST be null
    - query should be a short search query that would retrieve the relevant past context.
    """
  end
end
