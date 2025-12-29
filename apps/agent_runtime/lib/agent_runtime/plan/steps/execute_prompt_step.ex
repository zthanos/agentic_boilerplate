defmodule AgentRuntime.Llm.Plan.Steps.ExecutePromptStep do
  @behaviour AgentRuntime.Llm.Plan.Step

  require Logger

  alias AgentRuntime.Llm.Plan.PlanContext
  alias AgentRuntime.Llm.Executor

  @impl true
  def name, do: "execute_prompt"

  @impl true
  def run(%PlanContext{} = ctx, opts) do
    mode = Keyword.get(opts, :mode, :non_stream)

    final_messages = PlanContext.final_messages(ctx)
    input = normalize_input(ctx.input, final_messages)

    conversation_id = Map.get(ctx.exec_meta || %{}, "conversation_id")

    # If you don’t have auth yet, keep a stable dev user id.
    # Later: derive from ctx.exec_meta or session/user claims.
    user_id = Map.get(ctx.exec_meta || %{}, "user_id") || "dev"

    # Persist user message only if conversation_id exists/valid
    user_turn =
      case safe_uuid(conversation_id) do
        {:ok, conv_id} ->
          module = conversations_module()

          case apply(module, :ensure_conversation!, [conv_id, user_id]) do
            :ok ->
              user_text = extract_latest_user_text(final_messages, input)

              case apply(module, :append_message!, [conv_id, "user", user_text, nil]) do
                {:ok, msg} -> {msg, user_text}
                {:error, _} -> {nil, user_text}
              end

            {:error, _} ->
              {nil, ""}
          end

        :error ->
          {nil, ""}
      end

    case mode do
      :stream ->
        on_chunk = Keyword.fetch!(opts, :on_chunk)

        # Accumulate assistant output in the current process
        buf_key = {:assistant_buf, make_ref()}
        Process.put(buf_key, "")

        wrapped_on_chunk = fn chunk ->
          # Accumulate
          prev = Process.get(buf_key, "")
          Process.put(buf_key, prev <> chunk)

          # Forward to SSE/UI
          on_chunk.(chunk)
        end

        result =
          Executor.execute_stream(
            ctx.profile,
            ctx.overrides,
            input,
            ctx.exec_meta,
            wrapped_on_chunk
          )

        assistant_text = Process.get(buf_key, "")
        Process.delete(buf_key)

        maybe_persist_and_ingest(conversation_id, user_id, user_turn, assistant_text, result)


        {:halt, result}

      _ ->
        result = Executor.execute(ctx.profile, ctx.overrides, input, ctx.exec_meta)
        assistant_text = extract_assistant_text_from_result(result) || ""
        maybe_persist_and_ingest(conversation_id, user_id, user_turn, assistant_text, result)

        {:halt, result}
    end
  end

  # -----------------------
  # Persistence + ingestion
  # -----------------------

  defp maybe_persist_and_ingest(conversation_id, user_id, {user_msg, user_text}, assistant_text, result) do
    case {safe_uuid(conversation_id), user_msg} do
      {{:ok, conv_id}, %{id: _}} ->
        module = conversations_module()
        _ = apply(module, :ensure_conversation!, [conv_id, user_id])

        assistant_text =
          case String.trim(to_string(assistant_text || "")) do
            "" ->
              Logger.warning("[execute_prompt] empty assistant_text; skipping assistant persist/ingest")
              nil
            txt ->
              txt
          end

        if is_binary(assistant_text) do
          case apply(module, :append_message!, [conv_id, "assistant", assistant_text, nil]) do
            {:ok, assistant_msg} ->
              # Pass the actual DB records with IDs
              try do
                ingest_module = ingest_module()

                apply(ingest_module, :ingest_turn!, [
                  conv_id,
                  user_msg,           # This already has :id
                  assistant_msg       # This has :id too
                ])
              rescue
                e ->
                  Logger.error("[execute_prompt] ingest failed: #{Exception.message(e)}")
              end

            {:error, _} ->
              :ok
          end
        end

      _ ->
        :ok
    end
  end

  defp conversations_module do
    Application.get_env(:agent_runtime, :conversations_adapter, AgentWeb.Conversations.Adapter)
  end

  defp ingest_module do
    Application.get_env(:agent_runtime, :ingest_adapter, AgentWeb.Memory.Ingestor)
  end

  defp safe_uuid(nil), do: :error

  defp safe_uuid(v) when is_binary(v) do
    trimmed = String.trim(v)
    # Simple UUID v4 validation (8-4-4-4-12 hex digits)
    if Regex.match?(~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i, trimmed) do
      {:ok, trimmed}
    else
      :error
    end
  end

  defp safe_uuid(_), do: :error

  defp extract_latest_user_text(final_messages, input) do
    # Prefer chat messages if present
    case final_messages
         |> Enum.reverse()
         |> Enum.find(fn m ->
           (Map.get(m, "role") || Map.get(m, :role) || "") in ["user", :user]
         end) do
      nil ->
        # For completion inputs
        case input do
          %{type: :completion, prompt: p} -> to_string(p)
          _ -> ""
        end

      m ->
        Map.get(m, "content") || Map.get(m, :content) ||
          ""
          |> to_string()
    end
  end

  # Very defensive extractor (adjust later once you confirm Executor’s exact return shape)
  defp extract_assistant_text_from_result({:ok, %{text: t}}), do: to_string(t)
  defp extract_assistant_text_from_result({:ok, %{content: t}}), do: to_string(t)
  defp extract_assistant_text_from_result({:ok, %{"text" => t}}), do: to_string(t)
  defp extract_assistant_text_from_result({:ok, %{"content" => t}}), do: to_string(t)
  defp extract_assistant_text_from_result(_), do: nil

  # -----------------------
  # Existing helpers (unchanged)
  # -----------------------

  defp normalize_input(input, final_messages) do
    type = Map.get(input, "type") || Map.get(input, :type)

    cond do
      type in ["chat", :chat] ->
        %{
          type: :chat,
          messages: Enum.map(final_messages, &normalize_message/1)
        }

      type in ["completion", :completion] ->
        prompt = Map.get(input, "prompt") || Map.get(input, :prompt) || ""
        %{type: :completion, prompt: to_string(prompt)}

      true ->
        input
    end
  end

  defp normalize_message(m) when is_map(m) do
    role = Map.get(m, "role") || Map.get(m, :role) || "user"
    content = Map.get(m, "content") || Map.get(m, :content) || ""

    %{
      role: normalize_role(role),
      content: to_string(content),
      name: Map.get(m, "name") || Map.get(m, :name),
      tool_call_id: Map.get(m, "tool_call_id") || Map.get(m, :tool_call_id)
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp normalize_role(r) when is_atom(r), do: r

  defp normalize_role(r) when is_binary(r) do
    case String.downcase(r) do
      "system" -> :system
      "developer" -> :developer
      "assistant" -> :assistant
      "tool" -> :tool
      _ -> :user
    end
  end
end
