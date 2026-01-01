defmodule AgentRuntime.Llm.PlanExecutor do
  @moduledoc """
  Policy-driven Plan Execution Engine.

  Key semantics:
  - Execution is always plan-driven (plan_id required).
  - Plan artifact is loaded from configured PlanStore (DI via AgentRuntime.Llm.Plan.Store.impl!/0).
  - Steps are resolved/validated at runtime (Resolver).
  - Each step runs with a phase in exec_meta and (optionally) parent_run_id derived from prior step debug trail.
  - Step opts are composed from:
      (a) per-step opts (opts[:step_opts][StepModule])
      (b) injected infra opts (assessor_profile, assessor_overrides, memory_store, mode, on_chunk)
      (c) plan policies (plan.policies["steps"][step_mod.name()])
  """

  require Logger

  alias AgentRuntime.Llm.Plan.PlanContext
  alias AgentRuntime.Llm.Plan.Resolver
  alias AgentRuntime.Llm.Plan.Store

  @typedoc """
  Engine result:
  - `{:ok, map}` – final low-level executor result (wrapped response, run_id, trace_id, etc.)
  - `{:ok, %{mode: :needs_clarification, trace_id: ..., question: ...}}`
  - `{:error, term}`
  """
  @type result ::
          {:ok, map()}
          | {:ok, %{mode: :needs_clarification, trace_id: String.t(), question: String.t()}}
          | {:error, term()}

  # -----------------------
  # Public API (plan-driven)
  # -----------------------

  @doc """
  Execute a plan (non-streaming). Requires :plan_id in opts.
  Optional: :plan_version (integer or :latest, default :latest).
  """
  @spec execute_plan(
          profile :: term(),
          overrides :: map(),
          input :: map(),
          exec_meta :: map(),
          keyword()
        ) ::
          result()
  def execute_plan(profile, overrides, input, exec_meta, opts \\ []) when is_map(exec_meta) do
    plan_id = Keyword.fetch!(opts, :plan_id)
    plan_version = Keyword.get(opts, :plan_version, :latest)

    execute_plan_with_plan(
      plan_id,
      plan_version,
      profile,
      overrides,
      input,
      exec_meta,
      opts |> Keyword.put(:mode, :non_stream)
    )
  end

  @doc """
  Execute a plan (streaming). Requires :plan_id in opts.
  Optional: :plan_version (integer or :latest, default :latest).
  """
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
    plan_id = Keyword.fetch!(opts, :plan_id)
    plan_version = Keyword.get(opts, :plan_version, :latest)

    execute_plan_with_plan(
      plan_id,
      plan_version,
      profile,
      overrides,
      input,
      exec_meta,
      opts
      |> Keyword.put(:mode, :stream)
      |> Keyword.put(:on_chunk, on_chunk)
    )
  end

  @doc """
  Low-level entrypoint:
  - Loads plan from store (latest or specific version)
  - Resolves steps to modules and validates contracts
  - Injects plan_id/plan_version/trace_id into exec_meta
  - Executes steps
  """
  @spec execute_plan_with_plan(
          plan_id :: String.t(),
          plan_version :: non_neg_integer() | :latest,
          profile :: term(),
          overrides :: map(),
          input :: map(),
          exec_meta :: map(),
          keyword()
        ) :: result()
  def execute_plan_with_plan(
        plan_id,
        plan_version \\ :latest,
        profile,
        overrides,
        input,
        exec_meta,
        opts \\ []
      )
      when is_binary(plan_id) and is_map(exec_meta) do
    store = Store.impl!()

    with {:ok, plan} <- load_plan(store, plan_id, plan_version),
         {:ok, steps} <- Resolver.resolve_steps(plan) do
      trace_id =
        Map.get(exec_meta, "trace_id") ||
          Map.get(exec_meta, :trace_id) ||
          generate_trace_id()

      exec_meta =
        exec_meta
        |> Map.put("trace_id", trace_id)
        |> Map.put("plan_id", plan.id)
        |> Map.put("plan_version", plan.version)

      ctx = %PlanContext{
        profile: profile,
        overrides: overrides || %{},
        input: input,
        exec_meta: exec_meta
      }

      run_steps(ctx, steps, opts, plan)
    end
  end

  # -----------------------
  # Internal
  # -----------------------

  defp load_plan(store, plan_id, :latest), do: store.get_latest(plan_id)
  defp load_plan(store, plan_id, version), do: store.get(plan_id, version)

  defp run_steps(%PlanContext{} = ctx, steps, opts, plan) when is_list(steps) do
    trace_id = Map.get(ctx.exec_meta, "trace_id")

    Logger.info("[PlanExecutor] start trace_id=#{trace_id} steps=#{length(steps)}")

    Logger.info(
      "[PlanExecutor] plan=#{ctx.exec_meta["plan_id"]}:#{ctx.exec_meta["plan_version"]} trace_id=#{trace_id}"
    )

    Enum.reduce_while(steps, {:cont, ctx}, fn step_mod, {:cont, ctx_acc} ->
      ensure_step!(step_mod)

      phase = step_phase_name(step_mod)
      parent_run_id = get_last_run_id(ctx_acc)

      ctx_with_phase = %{
        ctx_acc
        | exec_meta:
            ctx_acc.exec_meta
            |> Map.put("phase", phase)
            |> maybe_put_parent_run_id(parent_run_id)
      }

      step_kw = step_opts(step_mod, opts, plan)

      try do
        Logger.info("[PlanExecutor] step=#{phase} parent_run_id=#{inspect(parent_run_id)}")

        case step_mod.run(ctx_with_phase, step_kw) do
          {:cont, %PlanContext{} = ctx2} ->
            {:cont, {:cont, ctx2}}

          {:halt, result} ->
            Logger.info("[PlanExecutor] halt at step=#{phase}")
            {:halt, result}

          other ->
            {:halt, {:error, {:invalid_step_return, step_mod, other}}}
        end
      rescue
        e ->
          Logger.error("[PlanExecutor] crash at step=#{phase}: #{Exception.message(e)}")
          {:halt, {:error, {:step_crashed, step_mod, Exception.message(e)}}}
      catch
        kind, reason ->
          Logger.error("[PlanExecutor] throw at step=#{phase}: #{inspect({kind, reason})}")
          {:halt, {:error, {:step_threw, step_mod, kind, reason}}}
      end
    end)
    |> case do
      {:cont, {:cont, last_ctx}} ->
        last_phase = Map.get(last_ctx.exec_meta || %{}, "phase")
        {:error, {:plan_did_not_halt, %{last_phase: last_phase}}}

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

  defp step_phase_name(step_mod) do
    case step_mod.name() do
      name when is_binary(name) ->
        trimmed_name = String.trim(name)

        if byte_size(trimmed_name) > 0 do
          trimmed_name
        else
          "custom_" <> Atom.to_string(step_mod)
        end

      _ ->
        "custom_" <> Atom.to_string(step_mod)
    end
  end

  defp get_last_run_id(%PlanContext{debug: debug}) when is_list(debug) do
    debug
    |> Enum.reverse()
    |> Enum.find_value(fn
      %{data: %{"run_id" => run_id}} when is_binary(run_id) and run_id != "" -> run_id
      %{data: %{run_id: run_id}} when is_binary(run_id) and run_id != "" -> run_id
      _ -> nil
    end)
  end

  defp get_last_run_id(_), do: nil

  defp maybe_put_parent_run_id(meta, nil), do: meta

  defp maybe_put_parent_run_id(meta, parent_run_id),
    do: Map.put(meta, "parent_run_id", parent_run_id)

  # Effective opts = base step opts (including infra injections) + plan per-step policies
  defp step_opts(step_mod, opts, plan) do
    base = step_opts_base(step_mod, opts)

    policies = plan.policies || %{}
    step_policy = get_in(policies, ["steps", step_mod.name()]) || %{}

    Keyword.merge(base, policy_to_keyword(step_policy))
  end

  # Convert JSON-style step policy to keyword opts safely (no String.to_atom/1).
  defp policy_to_keyword(nil), do: []

  defp policy_to_keyword(%{} = m) do
    allowed = %{
      "system_prompt" => :system_prompt,
      "top_k" => :top_k,
      "similarity_threshold" => :similarity_threshold,
      "min_score" => :min_score,
      "assessor_profile" => :assessor_profile,
      "assessor_overrides" => :assessor_overrides,
      "execution_overrides" => :execution_overrides
    }

    Enum.reduce(m, [], fn {k, v}, acc ->
      case Map.get(allowed, k) do
        nil -> acc
        atom_key -> [{atom_key, v} | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp policy_to_keyword(list) when is_list(list) do
    if Keyword.keyword?(list), do: list, else: []
  end

  defp policy_to_keyword(_), do: []

  defp step_opts_base(step_mod, opts) do
    per_step = Keyword.get(opts, :step_opts, %{})
    base = Map.get(per_step, step_mod, [])

    base =
      base
      |> maybe_put(:assessor_profile, Keyword.get(opts, :assessor_profile))
      |> maybe_put(:assessor_overrides, Keyword.get(opts, :assessor_overrides))
      |> maybe_put(:memory_store, Keyword.get(opts, :memory_store))

    case step_mod do
      AgentRuntime.Llm.Plan.Steps.ExecutePromptStep ->
        Keyword.merge(base, Keyword.take(opts, [:mode, :on_chunk]))

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
