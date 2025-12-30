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

      aug = normalize_chat_messages(ctx.augmented_messages || [])

      messages =
        [%{role: :system, content: system_prompt}] ++
        aug ++
        [%{role: :user, content: user_prompt}]

      llm_input = %{
        type: :chat,
        messages: messages
      }

      roles =
        messages
        |> Enum.map(fn
          %{role: r} -> r
          %{"role" => r} -> r
          _ -> :unknown
        end)

      has_user =
        Enum.any?(messages, fn
          %{role: :user} -> true
          %{role: "user"} -> true
          %{"role" => "user"} -> true
          _ -> false
        end)

      Logger.debug("[execute] llm_input messages_count=#{length(messages)} roles=#{inspect(roles)} has_user=#{has_user} messages=#{inspect(llm_input)}")


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

  defp normalize_chat_messages(messages) when is_list(messages) do
    Enum.map(messages, &normalize_chat_message/1)
  end

  defp normalize_chat_message(%{role: _r, content: _c} = m), do: m

  defp normalize_chat_message(%{"role" => r, "content" => c}) do
    %{
      role: normalize_role(r),
      content: c
    }
  end

  defp normalize_chat_message(other) do
    # Defensive: keep something usable for debugging instead of crashing.
    %{
      role: :system,
      content: "Unrecognized augmented message: " <> inspect(other)
    }
  end

  defp normalize_role(r) when is_atom(r), do: r
  defp normalize_role("system"), do: :system
  defp normalize_role("user"), do: :user
  defp normalize_role("assistant"), do: :assistant
  defp normalize_role(_), do: :system


  defp build_system_prompt do
    """
    You are deciding whether a user's request is clear enough to execute.

    Return ONLY valid JSON.

    Schema:
    {
      "needs_clarification": boolean,
      "question": string | null
    }

    Core rules:
    - Default to needs_clarification = false. Ask for clarification ONLY as a last resort.
    - If the request is answerable with reasonable assumptions, proceed (needs_clarification=false).
    - If the user message is empty or nonsensical, ask one short clarification question.

    Context rules (IMPORTANT):
    - You may be given additional context messages (e.g., retrieved memory or working context).
      If such context is present, you MUST use it to resolve references (it/that/this/they) and follow-ups.
    - If the user asks a follow-up, assume it refers to the immediately prior topic in the provided context.
    - Do NOT ask "what do you mean by it?" if the provided context gives a plausible antecedent.

    Comparison questions:
    - If the user asks "How does X compare with Y?" and context provides info about X,
      you can answer even if Y is not in the context - the assistant knows about Y.
    - Only ask for clarification if BOTH X and Y are unclear.

    When to ask clarification:
    - Ask clarification only if you genuinely cannot identify what the user is asking even after using the provided context.
    - If clarification is needed, ask exactly ONE short, specific question.

    Output rules:
    - If needs_clarification = false -> question MUST be null.
    - If needs_clarification = true  -> question MUST be a single short question.

    Examples:
    - "how can I call you?" -> needs_clarification: false
    - "what do you prefer?" -> needs_clarification: false (use context)
    - "yes" -> needs_clarification: false (use context)
    - "you choose" -> needs_clarification: false (use context)
    - "How does that compare with SSE?" -> needs_clarification: false (context has "that", SSE is known)
    - "" -> needs_clarification: true, question: "What would you like to know?"
    - "I need help with..." -> needs_clarification: true, question: "What specifically do you need help with?"
    """
  end

end
