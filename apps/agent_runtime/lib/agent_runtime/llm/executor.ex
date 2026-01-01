defmodule AgentRuntime.Llm.Executor do
  @moduledoc false

  alias AgentCore.Llm.{Profiles, ProviderRequest, ProviderResponse, Resolver, RunSnapshots, Runs}
  alias AgentRuntime.Llm.{ModelResolver, ProviderRegistry}

  # New arity (controller uses this)
  def execute(profile, overrides, input, exec_meta) when is_map(exec_meta) do
    do_execute(profile, overrides, input, exec_meta)
  end

  # Keep old arity for existing callers
  def execute(profile, overrides, input) do
    do_execute(profile, overrides, input, %{})
  end

  defp do_execute(profile, overrides, input, exec_meta) do
    started_at = System.monotonic_time(:millisecond)

    invocation = Resolver.resolve(profile, overrides)

    meta =
      %{
        trace_id: Map.get(exec_meta, "trace_id") || Map.get(exec_meta, :trace_id),
        parent_run_id: Map.get(exec_meta, "parent_run_id") || Map.get(exec_meta, :parent_run_id),
        phase: Map.get(exec_meta, "phase") || Map.get(exec_meta, :phase)
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    snapshot = RunSnapshots.from_config(invocation, invocation.overrides, meta)

    # Persist + use run_id for lifecycle
    run_id =
      case Runs.put(snapshot) do
        {:ok, rid} -> rid
        {:error, e} -> return_persist_error(e, snapshot)
      end

    _ = Runs.mark_started(run_id)

    resolved_model = ModelResolver.resolve(invocation.provider, invocation.model)

    request =
      ProviderRequest.new(invocation, input, [], %{
        "profile_id" => to_string(invocation.profile_id),
        "provider" => to_string(invocation.provider),
        "model" => to_string(invocation.model),
        "resolved_model" => resolved_model,
        "policy_version" => invocation.policy_version,
        "fingerprint" => invocation.fingerprint,
        "run_id" => run_id,
        "trace_id" => snapshot.trace_id
      })

    :telemetry.execute(
      [:agent_runtime, :llm, :execute, :start],
      %{system_time: System.system_time()},
      %{
        provider: invocation.provider,
        model: invocation.model,
        resolved_model: resolved_model,
        run_id: run_id,
        trace_id: snapshot.trace_id
      }
    )

    with {:ok, adapter} <- ProviderRegistry.adapter(invocation.provider),
         {:ok, resp} <- adapter.call(request) do
      latency = System.monotonic_time(:millisecond) - started_at

      _ =
        Runs.mark_finished(run_id, %{
          usage: resp.usage,
          latency_ms: latency
        })

      :telemetry.execute(
        [:agent_runtime, :llm, :execute, :stop],
        %{duration_ms: latency},
        %{
          provider: invocation.provider,
          model: invocation.model,
          resolved_model: resolved_model,
          usage: resp.usage,
          status: :ok,
          run_id: run_id,
          trace_id: snapshot.trace_id
        }
      )

      {:ok,
       %{
         response: resp,
         run_id: run_id,
         trace_id: snapshot.trace_id,
         fingerprint: snapshot.fingerprint,
         latency_ms: latency
       }}
    else
      {:error, reason} ->
        latency = System.monotonic_time(:millisecond) - started_at

        _ = Runs.mark_failed(run_id, reason, %{latency_ms: latency})

        :telemetry.execute(
          [:agent_runtime, :llm, :execute, :error],
          %{duration_ms: latency},
          %{
            provider: invocation.provider,
            model: invocation.model,
            resolved_model: resolved_model,
            reason: reason,
            status: :error,
            run_id: run_id,
            trace_id: snapshot.trace_id
          }
        )

        {:error,
         %{
           reason: reason,
           run_id: run_id,
           trace_id: snapshot.trace_id,
           fingerprint: snapshot.fingerprint,
           latency_ms: latency
         }}
    end
  end

  def execute_stream(profile, overrides, input, exec_meta, on_chunk)
      when is_map(exec_meta) and is_function(on_chunk, 1) do
    started_at = System.monotonic_time(:millisecond)

    invocation = Resolver.resolve(profile, overrides)

    meta =
      %{
        trace_id: Map.get(exec_meta, "trace_id") || Map.get(exec_meta, :trace_id),
        parent_run_id: Map.get(exec_meta, "parent_run_id") || Map.get(exec_meta, :parent_run_id),
        phase: Map.get(exec_meta, "phase") || Map.get(exec_meta, :phase)
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    snapshot = RunSnapshots.from_config(invocation, invocation.overrides, meta)

    run_id =
      case Runs.put(snapshot) do
        {:ok, rid} -> rid
        {:error, e} -> return_persist_error(e, snapshot)
      end

    _ = Runs.mark_started(run_id)

    resolved_model = ModelResolver.resolve(invocation.provider, invocation.model)

    request =
      ProviderRequest.new(invocation, input, [], %{
        "profile_id" => to_string(invocation.profile_id),
        "provider" => to_string(invocation.provider),
        "model" => to_string(invocation.model),
        "resolved_model" => resolved_model,
        "policy_version" => invocation.policy_version,
        "fingerprint" => invocation.fingerprint,
        "run_id" => run_id,
        "trace_id" => snapshot.trace_id
      })

    :telemetry.execute(
      [:agent_runtime, :llm, :execute, :start],
      %{system_time: System.system_time()},
      %{
        provider: invocation.provider,
        model: invocation.model,
        resolved_model: resolved_model,
        run_id: run_id,
        trace_id: snapshot.trace_id
      }
    )

    with {:ok, adapter} <- ProviderRegistry.adapter(invocation.provider),
         {:ok, resp} <- do_stream(adapter, request, on_chunk) do
      latency = System.monotonic_time(:millisecond) - started_at

      _ =
        Runs.mark_finished(run_id, %{
          usage: resp.usage,
          latency_ms: latency
        })

      :telemetry.execute(
        [:agent_runtime, :llm, :execute, :stop],
        %{duration_ms: latency},
        %{
          provider: invocation.provider,
          model: invocation.model,
          resolved_model: resolved_model,
          usage: resp.usage,
          status: :ok,
          run_id: run_id,
          trace_id: snapshot.trace_id
        }
      )

      {:ok,
       %{
         response: resp,
         run_id: run_id,
         trace_id: snapshot.trace_id,
         fingerprint: snapshot.fingerprint,
         latency_ms: latency
       }}
    else
      {:error, reason} ->
        latency = System.monotonic_time(:millisecond) - started_at
        _ = Runs.mark_failed(run_id, reason, %{latency_ms: latency})

        :telemetry.execute(
          [:agent_runtime, :llm, :execute, :error],
          %{duration_ms: latency},
          %{
            provider: invocation.provider,
            model: invocation.model,
            resolved_model: resolved_model,
            reason: reason,
            status: :error,
            run_id: run_id,
            trace_id: snapshot.trace_id
          }
        )

        {:error,
         %{
           reason: reason,
           run_id: run_id,
           trace_id: snapshot.trace_id,
           fingerprint: snapshot.fingerprint,
           latency_ms: latency
         }}
    end
  end

  # -------------------------
  # Embeddings
  # -------------------------

  @doc """
  Keyword API used by plan steps and ingestion:

    Executor.embed(profile_id: "embeddings_nomic_v15", input: "text", exec_meta: %{}, overrides: %{})

  Returns:
    {:ok, embedding_vector} for single string input
    {:ok, [embedding_vector, ...]} for list input
  """
  def embed(opts) when is_list(opts) do
    profile_id = Keyword.fetch!(opts, :profile_id)
    input = Keyword.fetch!(opts, :input)
    exec_meta = Keyword.get(opts, :exec_meta, %{})
    overrides = Keyword.get(opts, :overrides, %{})

    profile = Profiles.get!(profile_id)

    with {:ok, %{response: resp}} <- embed(profile, overrides, input, exec_meta),
         {:ok, vectors} <- extract_embedding_vectors(resp) do
      {:ok, finalize_embedding_return(input, vectors)}
    end
  end

  defp finalize_embedding_return(input, vectors) when is_binary(input) do
    case vectors do
      [v | _] -> v
      _ -> []
    end
  end

  defp finalize_embedding_return(_input, vectors), do: vectors

  # Accept common OpenAI-compatible shapes:
  # %{data: [%{embedding: [...]}, ...]} or %{"data" => [%{"embedding" => [...]}, ...]}
  defp extract_embedding_vectors(%ProviderResponse{raw: raw}) when is_map(raw) do
    data = Map.get(raw, :data) || Map.get(raw, "data")

    vectors =
      if is_list(data) do
        data
        |> Enum.map(fn item ->
          Map.get(item, :embedding) || Map.get(item, "embedding")
        end)
        |> Enum.filter(&is_list/1)
      else
        []
      end

    case vectors do
      [] -> {:error, {:invalid_embedding_response, raw}}
      _ -> {:ok, vectors}
    end
  end

  @doc """
  Non-stream embeddings execution with run persistence and full audit trail.

  `texts` can be a binary or list of binaries.

  Returns the same envelope shape as execute/4:
    {:ok, %{response: resp, run_id: ..., trace_id: ..., fingerprint: ..., latency_ms: ...}}
  """
  def embed(profile, overrides, texts) do
    embed(profile, overrides, texts, %{})
  end

  def embed(profile, overrides, texts, exec_meta) when is_map(exec_meta) do
    started_at = System.monotonic_time(:millisecond)

    invocation = Resolver.resolve(profile, overrides)

    meta =
      %{
        trace_id: Map.get(exec_meta, "trace_id") || Map.get(exec_meta, :trace_id),
        parent_run_id: Map.get(exec_meta, "parent_run_id") || Map.get(exec_meta, :parent_run_id),
        # default phase if not provided
        phase: Map.get(exec_meta, "phase") || Map.get(exec_meta, :phase) || "embed"
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    snapshot = RunSnapshots.from_config(invocation, invocation.overrides, meta)

    run_id =
      case Runs.put(snapshot) do
        {:ok, rid} -> rid
        {:error, e} -> return_persist_error(e, snapshot)
      end

    _ = Runs.mark_started(run_id)

    resolved_model = ModelResolver.resolve(invocation.provider, invocation.model)

    embedding_input = normalize_embedding_input(texts)

    request =
      ProviderRequest.new(invocation, embedding_input, [], %{
        "profile_id" => to_string(invocation.profile_id),
        "provider" => to_string(invocation.provider),
        "model" => to_string(invocation.model),
        "resolved_model" => resolved_model,
        "policy_version" => invocation.policy_version,
        "fingerprint" => invocation.fingerprint,
        "run_id" => run_id,
        "trace_id" => snapshot.trace_id
      })

    :telemetry.execute(
      [:agent_runtime, :llm, :embed, :start],
      %{system_time: System.system_time()},
      %{
        provider: invocation.provider,
        model: invocation.model,
        resolved_model: resolved_model,
        run_id: run_id,
        trace_id: snapshot.trace_id
      }
    )

    with {:ok, adapter} <- ProviderRegistry.adapter(invocation.provider),
         {:ok, resp} <- adapter.call(request) do
      latency = System.monotonic_time(:millisecond) - started_at

      _ =
        Runs.mark_finished(run_id, %{
          usage: resp.usage,
          latency_ms: latency
        })

      :telemetry.execute(
        [:agent_runtime, :llm, :embed, :stop],
        %{duration_ms: latency},
        %{
          provider: invocation.provider,
          model: invocation.model,
          resolved_model: resolved_model,
          usage: resp.usage,
          status: :ok,
          run_id: run_id,
          trace_id: snapshot.trace_id
        }
      )

      {:ok,
       %{
         response: resp,
         run_id: run_id,
         trace_id: snapshot.trace_id,
         fingerprint: snapshot.fingerprint,
         latency_ms: latency
       }}
    else
      {:error, reason} ->
        latency = System.monotonic_time(:millisecond) - started_at
        _ = Runs.mark_failed(run_id, reason, %{latency_ms: latency})

        :telemetry.execute(
          [:agent_runtime, :llm, :embed, :error],
          %{duration_ms: latency},
          %{
            provider: invocation.provider,
            model: invocation.model,
            resolved_model: resolved_model,
            reason: reason,
            status: :error,
            run_id: run_id,
            trace_id: snapshot.trace_id
          }
        )

        {:error,
         %{
           reason: reason,
           run_id: run_id,
           trace_id: snapshot.trace_id,
           fingerprint: snapshot.fingerprint,
           latency_ms: latency
         }}
    end
  end

  defp normalize_embedding_input(texts) when is_binary(texts) do
    %{
      type: :embedding,
      input: [texts]
    }
  end

  defp normalize_embedding_input(texts) when is_list(texts) do
    cleaned =
      texts
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    %{
      type: :embedding,
      input: cleaned
    }
  end

  defp do_stream(adapter, request, on_chunk) do
    cond do
      function_exported?(adapter, :stream, 2) ->
        adapter.stream(request, on_chunk)

      true ->
        # fallback: non-streaming adapter
        with {:ok, resp} <- adapter.call(request) do
          text = Map.get(resp, :output_text) || ""
          _ = on_chunk.(text)
          {:ok, resp}
        end
    end
  end

  defp return_persist_error(e, snapshot) do
    throw(
      {:run_persist_failed, %{error: e, run_id: snapshot.run_id, trace_id: snapshot.trace_id}}
    )
  end
end
