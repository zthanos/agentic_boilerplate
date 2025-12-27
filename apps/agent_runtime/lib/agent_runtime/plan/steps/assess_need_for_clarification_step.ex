defmodule AgentRuntime.Llm.Plan.Steps.AssessNeedForClarificationStep do
  @behaviour AgentRuntime.Llm.Plan.Step
  require Logger

  alias AgentRuntime.Llm.Plan.PlanContext
  alias AgentRuntime.Llm.Plan.StepUtils
  alias AgentRuntime.Llm.Executor

  @impl true
  def name, do: "assess_need_for_clarification"

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
        |> PlanContext.put_decision(:needs_clarification, false)
        |> PlanContext.put_decision(:clarification_question, nil)
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

      # Execute with current phase from exec_meta (will be "assess_clarification")
      case Executor.execute(assessor_profile, overrides, llm_input, ctx.exec_meta) do
        {:ok, %{response: %{output_text: text}, run_id: run_id}} ->
          result_map =
            text
            |> StepUtils.safe_json_decode()
            |> StepUtils.enforce_null_when_false("needs_clarification", "question")

          needs = StepUtils.boolean(result_map, "needs_clarification", false)
          question = StepUtils.string_or_nil(result_map, "question")

          ctx =
            ctx
            |> PlanContext.put_decision(:needs_clarification, needs)
            |> PlanContext.put_decision(:clarification_question, question)
            |> PlanContext.add_debug(name(), %{
              "needs_clarification" => needs,
              "question" => question,
              "run_id" => run_id
            })

          if needs and is_binary(question) do
            trace_id = Map.get(ctx.exec_meta, "trace_id") || Map.get(ctx.exec_meta, :trace_id)
            Logger.info("[plan] Clarification needed, halting. run_id=#{run_id}")
            {:halt, {:ok, %{mode: :needs_clarification, trace_id: trace_id, question: question, run_id: run_id}}}
          else
            Logger.info("[plan] No clarification needed. run_id=#{run_id}")
            {:cont, ctx}
          end

        {:error, %{reason: reason, run_id: run_id}} ->
          ctx =
            ctx
            |> PlanContext.put_decision(:needs_clarification, false)
            |> PlanContext.put_decision(:clarification_question, nil)
            |> PlanContext.add_debug(name(), %{
              "assess_error" => inspect(reason),
              "run_id" => run_id
            })

          Logger.warning("[plan] assess_clarification error: #{inspect(reason)}")
          {:cont, ctx}

        other ->
          ctx = PlanContext.add_debug(ctx, name(), %{"assess_unexpected" => inspect(other)})
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
    You are deciding whether a user's request is clear enough to execute.

    Return ONLY valid JSON.

    Schema:
    {
      "needs_clarification": boolean,
      "question": string | null
    }

    Rules:
    - If the request is ambiguous, missing goals, or unclear -> needs_clarification = true
    - If needs_clarification = false -> question MUST be null
    - Keep the question short and specific.
    """
  end
end
