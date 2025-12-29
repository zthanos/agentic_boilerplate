defmodule AgentRuntime.Llm.PlanExecutor do
  @moduledoc """
  Plan-driven execution wrapper with phase-based RunSnapshot tracking.

  Each step execution is tracked with its own phase in RunSnapshot:
  - "assess_history" - History assessment step
  - "assess_clarification" - Clarification assessment step
  - "retrieve_memory" - Memory retrieval step
  - "execute" - Final prompt execution step

  This enables end-to-end observability of the entire plan execution.
  """
  require Logger
  alias AgentRuntime.Llm.Plan.PlanContext
  # alias AgentCore.Llm.RunSnapshot

  @default_steps [
    AgentRuntime.Llm.Plan.Steps.AssessNeedForHistoryStep,
    AgentRuntime.Llm.Plan.Steps.AssessNeedForClarificationStep,
    AgentRuntime.Llm.Plan.Steps.RetrieveMemoryStep,
    AgentRuntime.Llm.Plan.Steps.ExecutePromptStep
  ]

  @type result ::
          AgentRuntime.Llm.Executor.result()
          | {:ok, %{mode: :needs_clarification, trace_id: String.t(), question: String.t()}}
          | {:error, term()}

  @spec execute_plan(profile :: term(), overrides :: map(), input :: map(), exec_meta :: map(), keyword()) ::
          result()
  def execute_plan(profile, overrides, input, exec_meta, opts \\ []) when is_map(exec_meta) do
    steps = Keyword.get(opts, :steps, @default_steps)

    # Ensure we have a trace_id for tracking the entire plan
    trace_id = Map.get(exec_meta, "trace_id") || Map.get(exec_meta, :trace_id) || generate_trace_id()

    ctx = %PlanContext{
      profile: profile,
      overrides: overrides || %{},
      input: input,
      exec_meta: Map.put(exec_meta, "trace_id", trace_id)
    }

    run_steps(ctx, steps, Keyword.put(opts, :mode, :non_stream))
  end

  @spec execute_plan_stream(
          profile :: term(),
          overrides :: map(),
          input :: map(),
          exec_meta :: map(),
          (binary() -> any()),
          keyword()
        ) :: result()
  def execute_plan_stream(profile, overrides, input, exec_meta, on_chunk, opts \\ [])
      when is_map(exec_meta) and is_function(on_chunk, 1) do
    steps = Keyword.get(opts, :steps, @default_steps)

    trace_id = Map.get(exec_meta, "trace_id") || Map.get(exec_meta, :trace_id) || generate_trace_id()

    ctx = %PlanContext{
      profile: profile,
      overrides: overrides || %{},
      input: input,
      exec_meta: Map.put(exec_meta, "trace_id", trace_id)
    }

    run_steps(ctx, steps, opts |> Keyword.put(:mode, :stream) |> Keyword.put(:on_chunk, on_chunk))
  end

  # -----------------------
  # Internal
  # -----------------------

  defp run_steps(%PlanContext{} = ctx, steps, opts) when is_list(steps) do
    trace_id = Map.get(ctx.exec_meta, "trace_id")
    Logger.info("[PlanExecutor] Starting plan execution trace_id=#{trace_id} steps=#{length(steps)}")

    Enum.reduce_while(steps, {:cont, ctx}, fn step_mod, {:cont, ctx_acc} ->
      ensure_step!(step_mod)

      # Determine phase name for this step
      phase = step_phase_name(step_mod)

      # Create parent_run_id from previous step if available
      parent_run_id = get_last_run_id(ctx_acc)

      # Update exec_meta with current phase and parent
      ctx_with_phase = %{
        ctx_acc
        | exec_meta:
            ctx_acc.exec_meta
            |> Map.put("phase", phase)
            |> maybe_put_parent_run_id(parent_run_id)
      }

      try do
        Logger.info("[PlanExecutor] Executing step=#{phase} parent_run_id=#{parent_run_id}")

        case step_mod.run(ctx_with_phase, step_opts(step_mod, opts)) do
          {:cont, %PlanContext{} = ctx2} ->
            # Step completed successfully, continue
            {:cont, {:cont, ctx2}}

          {:halt, result} ->
            # Step decided to halt (either success or needs_clarification)
            Logger.info("[PlanExecutor] Step #{phase} halted execution")
            {:halt, result}

          other ->
            {:halt, {:error, {:invalid_step_return, step_mod, other}}}
        end
      rescue
        e ->
          Logger.error("[PlanExecutor] Step #{phase} crashed: #{Exception.message(e)}")
          {:halt, {:error, {:step_crashed, step_mod, Exception.message(e)}}}
      catch
        kind, reason ->
          Logger.error("[PlanExecutor] Step #{phase} threw: #{inspect({kind, reason})}")
          {:halt, {:error, {:step_threw, step_mod, kind, reason}}}
      end
    end)
    |> case do
      {:cont, {:cont, _ctx}} ->
        {:error, :plan_did_not_halt}

      other ->
        other
    end
  end

  defp ensure_step!(mod) do
    unless Code.ensure_loaded?(mod) do
      raise ArgumentError, "Plan step module not loaded: #{inspect(mod)}"
    end

    unless function_exported?(mod, :run, 2) and function_exported?(mod, :name, 0) do
      raise ArgumentError, "Invalid plan step module: #{inspect(mod)}"
    end

    :ok
  end

  # Map step modules to phase names for RunSnapshot tracking
  defp step_phase_name(AgentRuntime.Llm.Plan.Steps.AssessNeedForHistoryStep), do: "assess_history"
  defp step_phase_name(AgentRuntime.Llm.Plan.Steps.AssessNeedForClarificationStep), do: "assess_clarification"
  defp step_phase_name(AgentRuntime.Llm.Plan.Steps.RetrieveMemoryStep), do: "retrieve_memory"
  defp step_phase_name(AgentRuntime.Llm.Plan.Steps.ExecutePromptStep), do: "execute"
  defp step_phase_name(other), do: "custom_#{inspect(other)}"

  # Extract the last run_id from debug trail for parent linking
  defp get_last_run_id(%PlanContext{debug: debug}) when is_list(debug) do
    debug
    |> Enum.reverse()
    |> Enum.find_value(fn entry ->
      Map.get(entry, :run_id) || get_in(entry, [:data, "run_id"]) || get_in(entry, [:data, :run_id])
    end)
  end
  defp get_last_run_id(_), do: nil

  defp maybe_put_parent_run_id(meta, nil), do: meta
  defp maybe_put_parent_run_id(meta, parent_run_id), do: Map.put(meta, "parent_run_id", parent_run_id)
  defp step_opts(step_mod, opts) do
    per_step = Keyword.get(opts, :step_opts, %{})
    base = Map.get(per_step, step_mod, [])

    base =
      base
      |> maybe_put(:assessor_profile, Keyword.get(opts, :assessor_profile))
      |> maybe_put(:assessor_overrides, Keyword.get(opts, :assessor_overrides))

    case step_mod do
      AgentRuntime.Llm.Plan.Steps.ExecutePromptStep ->
        Keyword.merge(base, Keyword.take(opts, [:mode, :on_chunk]))

      AgentRuntime.Llm.Plan.Steps.RetrieveMemoryStep ->
        Keyword.put_new(base, :memory_store, AgentWeb.Memory.Store)

      _ ->
        base
    end
  end


  defp maybe_put(keyword, _k, nil), do: keyword
  defp maybe_put(keyword, k, v), do: Keyword.put_new(keyword, k, v)

  defp generate_trace_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
