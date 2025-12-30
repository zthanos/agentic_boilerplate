defmodule AgentRuntime.Llm.AgentExecutor do
  @moduledoc """
  Executes an Agent (agent_id/version) by:
  1) loading AgentDefinition
  2) loading referenced PlanDefinition
  3) executing the plan via PlanExecutor
  """

  alias AgentRuntime.Llm.Agent.Store, as: AgentStoreDI
  # alias AgentRuntime.Llm.Plan.Store, as: PlanStoreDI
  alias AgentRuntime.Llm.PlanExecutor

  def execute_agent(profile, overrides, input, exec_meta, opts \\ []) do
    agent_id = Keyword.fetch!(opts, :agent_id)
    agent_version = Keyword.get(opts, :agent_version, :latest)

    with {:ok, agent} <- load_agent(agent_id, agent_version) do
      exec_meta = inject_agent_meta(exec_meta, agent)
      {plan_id, plan_ver} = agent_plan(agent)

      PlanExecutor.execute_plan_with_plan(
        plan_id,
        plan_ver,
        profile,
        overrides,
        input,
        exec_meta,
        plan_opts_from_agent(opts, agent)
      )
    end
  end

  def execute_agent_stream(profile, overrides, input, exec_meta, on_chunk, opts \\ []) do
    agent_id = Keyword.fetch!(opts, :agent_id)
    agent_version = Keyword.get(opts, :agent_version, :latest)

    with {:ok, agent} <- load_agent(agent_id, agent_version) do
      exec_meta = inject_agent_meta(exec_meta, agent)
      {plan_id, plan_ver} = agent_plan(agent)

      PlanExecutor.execute_plan_with_plan(
        plan_id,
        plan_ver,
        profile,
        overrides,
        input,
        exec_meta,
        opts
        |> Keyword.put(:mode, :stream)
        |> Keyword.put(:on_chunk, on_chunk)
        |> plan_opts_from_agent(agent)
      )
    end
  end

  defp load_agent(agent_id, :latest) do
    AgentStoreDI.impl!().get_latest(agent_id)
  end

  defp load_agent(agent_id, version) do
    AgentStoreDI.impl!().get(agent_id, version)
  end

  defp agent_plan(agent) do
    plan = agent.plan
    plan_id = plan["id"] || plan[:id]
    plan_ver = plan["version"] || plan[:version] || :latest
    {plan_id, plan_ver}
  end

  defp inject_agent_meta(exec_meta, agent) do
    sys = agent.prompts["system"] || agent.prompts[:system]

    exec_meta
    |> Map.put("agent_id", agent.id)
    |> Map.put("agent_version", agent.version)
    |> maybe_put("agent_system_prompt", sys)
  end

  # For now we just pass-through opts and rely on PlanExecutor policy merge.
  # Later: merge agent.policies over plan.policies if you want a true precedence model.
  defp plan_opts_from_agent(opts, _agent), do: opts

  defp maybe_put(m, _k, nil), do: m
  defp maybe_put(m, k, v), do: Map.put(m, k, v)
end
