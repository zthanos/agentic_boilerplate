# defmodule AgentRuntime.Llm.Plan.Steps.AssessNeedForHistoryStep do
#   @behaviour AgentRuntime.Llm.Plan.Step

#   require Logger

#   alias AgentRuntime.Llm.Plan.PlanContext
#   alias AgentRuntime.Llm.Plan.StepUtils
#   alias AgentRuntime.Llm.Executor

#   @impl true
#   def name, do: "assess_need_for_history"

#   @impl true
#   def run(%PlanContext{} = ctx, opts) do
#     assessor_profile = resolve_assessor_profile(ctx, opts)

#     overrides =
#       Keyword.get(opts, :assessor_overrides, %{
#         "generation" => %{"temperature" => 0},
#         "budgets" => %{"request_timeout_ms" => 8_000, "max_retries" => 0}
#       })

#     user_prompt = StepUtils.last_user_prompt(ctx)
#     executor = Keyword.get(opts, :executor, Executor)

#     cond do
#       is_nil(user_prompt) or String.trim(user_prompt) == "" ->
#         {:cont,
#          ctx
#          |> PlanContext.put_decision(:history_query, nil)
#          |> PlanContext.add_debug(name(), %{
#            "skipped" => true,
#            "reason" => "missing_or_blank_user_prompt"
#          })}

#       is_nil(assessor_profile) ->
#         {:cont,
#          ctx
#          |> PlanContext.put_decision(:history_query, nil)
#          |> PlanContext.add_debug(name(), %{
#            "skipped" => true,
#            "reason" => "assessor_profile_missing_or_invalid"
#          })}

#       true ->
#         case StepUtils.require_nonblank_opt!(opts, :system_prompt, name()) do
#           {:ok, system_prompt} ->
#             execute_history_assessment(
#               ctx,
#               executor,
#               assessor_profile,
#               overrides,
#               system_prompt,
#               user_prompt
#             )

#           {:error, reason} ->
#             _ctx =
#               ctx
#               |> PlanContext.add_debug(name(), %{
#                 "skipped" => true,
#                 "reason" => "missing_required_policy_system_prompt",
#                 "detail" => inspect(reason)
#               })

#             {:halt, {:error, {:missing_policy, name(), :system_prompt}}}
#         end
#     end
#   end

#   defp resolve_assessor_profile(%PlanContext{} = ctx, opts) do
#     case Keyword.get(opts, :assessor_profile) do
#       p when is_map(p) -> p
#       _ -> if(is_map(ctx.profile), do: ctx.profile, else: nil)
#     end
#   end

#   defp execute_history_assessment(
#          ctx,
#          executor,
#          assessor_profile,
#          overrides,
#          system_prompt,
#          user_prompt
#        ) do
#     llm_input = %{
#       type: :chat,
#       messages: [
#         %{role: :system, content: system_prompt},
#         %{role: :user, content: user_prompt}
#       ]
#     }

#     case executor.execute(assessor_profile, overrides, llm_input, ctx.exec_meta) do
#       {:ok, %{response: %{output_text: text}, run_id: run_id}} ->
#         Logger.info("[plan] assess_history raw LLM output: #{inspect(text)}")

#         query =
#           text
#           |> StepUtils.safe_json_decode()
#           |> StepUtils.string_or_nil("query")

#         Logger.info("[plan] assess_history parsed query: #{inspect(query)}")
#         Logger.info("[plan] assess_history completed: query=#{inspect(query)} run_id=#{run_id}")

#         {:cont,
#          ctx
#          |> PlanContext.put_decision(:history_query, query)
#          |> PlanContext.add_debug(name(), %{"query" => query, "run_id" => run_id})}

#       {:error, %{reason: reason, run_id: run_id}} ->
#         Logger.warning("[plan] assess_history error: #{inspect(reason)}")

#         {:cont,
#          ctx
#          |> PlanContext.put_decision(:history_query, nil)
#          |> PlanContext.add_debug(name(), %{"assess_error" => inspect(reason), "run_id" => run_id})}

#       other ->
#         Logger.warning("[plan] assess_history unexpected: #{inspect(other)}")

#         {:cont,
#          ctx
#          |> PlanContext.put_decision(:history_query, nil)
#          |> PlanContext.add_debug(name(), %{"assess_unexpected" => inspect(other)})}
#     end
#   end
# end
