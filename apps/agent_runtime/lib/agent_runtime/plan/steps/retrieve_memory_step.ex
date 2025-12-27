# retrieve_memory_step.ex
defmodule AgentRuntime.Llm.Plan.Steps.RetrieveMemoryStep do
  @behaviour AgentRuntime.Llm.Plan.Step
  require Logger

  alias AgentRuntime.Llm.Plan.PlanContext

  @impl true
  def name, do: "retrieve_memory"

  @impl true
  def run(%PlanContext{} = ctx, _opts) do
    # v0: NOOP but still tracked with phase="retrieve_memory"
    # Future: actual memory retrieval based on ctx.decisions.needs_history

    # Generate a synthetic run_id for this step (or skip if not needed)
    run_id = generate_run_id()

    ctx = PlanContext.add_debug(ctx, name(), %{
      "status" => "noop",
      "run_id" => run_id,
      "phase" => "retrieve_memory"
    })

    Logger.info("[plan] retrieve_memory step (noop) run_id=#{run_id}")
    {:cont, ctx}
  end

  defp generate_run_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
