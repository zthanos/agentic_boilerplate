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

    overrides =
      Keyword.get(opts, :assessor_overrides, %{
        "generation" => %{"temperature" => 0},
        "budgets" => %{"request_timeout_ms" => 8_000, "max_retries" => 0}
      })

    cond do
      is_nil(assessor_profile) ->
        ctx =
          ctx
          |> PlanContext.put_decision(:needs_clarification, false)
          |> PlanContext.put_decision(:clarification_question, nil)
          |> PlanContext.add_debug(name(), %{
            "skipped" => true,
            "reason" => "assessor_profile_missing_or_invalid"
          })

        {:cont, ctx}

      true ->
        user_prompt = StepUtils.last_user_prompt(ctx)

        case StepUtils.require_nonblank_opt!(opts, :system_prompt, name()) do
          {:ok, system_prompt} ->
            execute_clarification_assessment(
              ctx,
              assessor_profile,
              overrides,
              system_prompt,
              user_prompt
            )

          {:error, reason} ->
            ctx
            |> PlanContext.put_decision(:needs_clarification, false)
            |> PlanContext.put_decision(:clarification_question, nil)
            |> PlanContext.add_debug(name(), %{
              "skipped" => true,
              "reason" => "missing_required_policy_system_prompt",
              "detail" => inspect(reason)
            })

            {:halt, {:error, {:missing_policy, name(), :system_prompt}}}
        end
    end
  end

  defp execute_clarification_assessment(
         ctx,
         assessor_profile,
         overrides,
         system_prompt,
         user_prompt
       ) do
    aug = normalize_chat_messages(ctx.augmented_messages || [])

    messages =
      [%{role: :system, content: system_prompt}] ++
        aug ++
        [%{role: :user, content: user_prompt}]

    llm_input = %{
      type: :chat,
      messages: messages
    }

    # Optional debug (be careful: can be verbose)
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

    Logger.debug(
      "[execute] llm_input messages_count=#{length(messages)} roles=#{inspect(roles)} has_user=#{has_user}"
    )

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

          {:halt,
           {:ok,
            %{mode: :needs_clarification, trace_id: trace_id, question: question, run_id: run_id}}}
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

  defp resolve_assessor_profile(%PlanContext{} = ctx, opts) do
    case Keyword.get(opts, :assessor_profile) do
      p when is_map(p) ->
        p

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
end
