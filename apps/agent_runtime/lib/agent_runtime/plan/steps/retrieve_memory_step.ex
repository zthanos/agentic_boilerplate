defmodule AgentRuntime.Llm.Plan.Steps.RetrieveMemoryStep do
  @behaviour AgentRuntime.Llm.Plan.Step
  require Logger

  alias AgentRuntime.Llm.Plan.PlanContext
  alias AgentRuntime.Llm.Executor

  @top_k 6
  @embeddings_profile_id "embeddings_nomic_v15"

  @impl true
  def name, do: "retrieve_memory"

  @impl true
  def run(%PlanContext{} = ctx, opts) do
    needs_history? = get_in(ctx.decisions || %{}, [:needs_history]) == true
    query_text = get_in(ctx.decisions || %{}, [:history_query])
    conversation_id = Map.get(ctx.exec_meta || %{}, "conversation_id")

    memory_store = Keyword.get(opts, :memory_store)

    cond do
      needs_history? == false -> {:cont, PlanContext.add_debug(ctx, name(), %{"skipped" => true, "reason" => "needs_history=false"})}
      blank?(query_text) -> {:cont, PlanContext.add_debug(ctx, name(), %{"skipped" => true, "reason" => "missing history_query"})}
      blank?(conversation_id) -> {:cont, PlanContext.add_debug(ctx, name(), %{"skipped" => true, "reason" => "missing conversation_id"})}
      is_nil(memory_store) -> {:cont, PlanContext.add_debug(ctx, name(), %{"skipped" => true, "reason" => "missing memory_store"})}

      true ->
        with {:ok, embedding} <- Executor.embed(profile_id: @embeddings_profile_id, input: query_text),
             results <- memory_store.search(conversation_id, embedding, @top_k) do
          # results: [%{id: ..., text: ..., score: ...}, ...]
          ctx =
            ctx
            |> maybe_inject(results)
            |> PlanContext.add_debug(name(), %{
              "conversation_id" => conversation_id,
              "query" => query_text,
              "chunks" => Enum.map(results, &Map.take(&1, [:id, :score]))
            })

          {:cont, ctx}
        else
          _ ->
            {:cont, PlanContext.add_debug(ctx, name(), %{"skipped" => true, "reason" => "embed_failed_or_no_results"})}
        end
    end
  end

  defp maybe_inject(ctx, []), do: ctx

  defp maybe_inject(ctx, results) do
    content =
      results
      |> Enum.map_join("\n\n", & &1.text)

    PlanContext.add_augmented_message(ctx, %{
      "role" => "system",
      "content" =>
        ("The following information was retrieved from prior conversation context.\n" <>
           "Use it only if relevant.\n\n" <> content)
        |> String.trim()
    })
  end

  defp blank?(v), do: is_nil(v) or (is_binary(v) and String.trim(v) == "")
end
