defmodule AgentRuntime.Llm.Plan.Steps.RetrieveMemoryStep do
  @behaviour AgentRuntime.Llm.Plan.Step
  require Logger

  alias AgentRuntime.Llm.Plan.PlanContext
  alias AgentRuntime.Llm.Executor

  @default_threshold 0.38
  @top_k 6
  @embeddings_profile_id "embeddings_nomic_v15"

  @impl true
  def name, do: "retrieve_memory"

  @impl true
  def run(%PlanContext{} = ctx, opts) do
    executor = Keyword.get(opts, :executor, Executor)
    memory_store = Keyword.get(opts, :memory_store)

    query_text = get_in(ctx.decisions || %{}, [:history_query])
    conversation_id = Map.get(ctx.exec_meta || %{}, "conversation_id")

    top_k = Keyword.get(opts, :top_k, Keyword.get(opts, :retrieval_top_k, @top_k))

    threshold =
      Keyword.get(opts, :similarity_threshold, Keyword.get(opts, :min_score, @default_threshold))

    Logger.info(
      "[plan] retrieve_memory starting: query=#{inspect(query_text)}, conv_id=#{inspect(conversation_id)}, store?=#{not is_nil(memory_store)}"
    )

    ctx =
      PlanContext.add_debug(ctx, name(), %{
        "history_query" => query_text,
        "exec_meta_conversation_id" => conversation_id,
        "has_memory_store" => not is_nil(memory_store),
        "top_k" => top_k,
        "threshold" => threshold
      })

    cond do
      blank?(query_text) ->
        Logger.info("[plan] retrieve_memory skipped: blank query_text")

        {:cont,
         PlanContext.add_debug(ctx, name(), %{
           "skipped" => true,
           "reason" => "missing history_query"
         })}

      blank?(conversation_id) ->
        Logger.info("[plan] retrieve_memory skipped: blank conversation_id")

        {:cont,
         PlanContext.add_debug(ctx, name(), %{
           "skipped" => true,
           "reason" => "missing conversation_id"
         })}

      is_nil(memory_store) ->
        Logger.info("[plan] retrieve_memory skipped: nil memory_store")

        {:cont,
         PlanContext.add_debug(ctx, name(), %{
           "skipped" => true,
           "reason" => "missing memory_store"
         })}

      true ->
        try do
          Logger.info("[plan] creating embedding for query: #{inspect(query_text)}")

          # IMPORTANT:
          # Use behaviour signature embed/4 (binary, map, map, map)
          embed_profile = %{"id" => @embeddings_profile_id}
          overrides = ctx.overrides || %{}
          exec_meta = ctx.exec_meta || %{}

          with {:ok, embedding} <- executor.embed(query_text, embed_profile, overrides, exec_meta) do
            Logger.info("[plan] embedding created, length: #{length(embedding)}")

            results =
              case call_search(memory_store, conversation_id, embedding, top_k) do
                {:ok, chunks} when is_list(chunks) -> chunks
                chunks when is_list(chunks) -> chunks
                other -> raise "memory_store.search returned unexpected: #{inspect(other)}"
              end

            Logger.info("[plan] search returned #{length(results)} results")

            Enum.each(Enum.take(results, 3), fn chunk ->
              preview =
                chunk.text
                |> to_string()
                |> String.slice(0, 50)

              Logger.info("[plan] Chunk preview: #{preview}... score: #{chunk.score}")
            end)

            max_score =
              results
              |> Enum.map(& &1.score)
              |> Enum.max(fn -> 0.0 end)

            selected = Enum.filter(results, &(&1.score >= threshold))

            Logger.info(
              "[plan] selected #{length(selected)} chunks above threshold #{threshold}, max_score=#{max_score}"
            )

            ctx =
              ctx
              |> PlanContext.put_decision(:needs_history, selected != [])
              |> maybe_inject(selected)
              |> PlanContext.add_debug(name(), %{
                "conversation_id" => conversation_id,
                "query" => query_text,
                "max_score" => max_score,
                "selected_count" => length(selected),
                "chunks" => Enum.map(results, &Map.take(&1, [:id, :score])),
                "selected_chunks" => Enum.map(selected, &Map.take(&1, [:id, :score]))
              })

            {:cont, ctx}
          else
            {:error, reason} ->
              Logger.error("[plan] embedding failed: #{inspect(reason)}")

              {:cont,
               PlanContext.add_debug(ctx, name(), %{
                 "skipped" => true,
                 "reason" => "embed_failed",
                 "details" => inspect(reason)
               })}

            other ->
              Logger.error("[plan] unexpected result from embedding: #{inspect(other)}")

              {:cont,
               PlanContext.add_debug(ctx, name(), %{
                 "skipped" => true,
                 "reason" => "embed_failed",
                 "details" => inspect(other)
               })}
          end
        rescue
          e ->
            Logger.error("[plan] retrieve_memory error: #{Exception.message(e)}")
            Logger.error(Exception.format_stacktrace(__STACKTRACE__))

            {:cont,
             PlanContext.add_debug(ctx, name(), %{
               "skipped" => true,
               "reason" => "exception",
               "details" => Exception.message(e)
             })}
        end
    end
  end

  # Supports either search/3 that returns {:ok, list} or list
  defp call_search(memory_store, conversation_id, embedding, top_k) do
    cond do
      function_exported?(memory_store, :search, 3) ->
        memory_store.search(conversation_id, embedding, top_k)

      function_exported?(memory_store, :search, 4) ->
        # In case your store expects opts map/kw
        memory_store.search(conversation_id, embedding, top_k, %{})

      true ->
        raise "memory_store does not implement search/3 or search/4"
    end
  end

  defp maybe_inject(ctx, []), do: ctx

  # RESTORE injection into augmented_messages (regression fix)
  defp maybe_inject(ctx, selected) do
    content =
      selected
      |> Enum.map_join("\n\n", fn chunk -> to_string(chunk.text) end)

    ctx
    |> PlanContext.put_decision(:retrieved_memory, selected)
    |> PlanContext.add_augmented_message(%{
      "role" => "system",
      "content" =>
        ("The following information was retrieved from prior conversation context.\n" <>
           "Use it only if relevant.\n\n" <> content)
        |> String.trim()
    })
  end

  defp blank?(v), do: is_nil(v) or (is_binary(v) and String.trim(v) == "")
end
