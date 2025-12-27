# lib/agent_runtime/llm/plan/steps/execute_prompt_step.ex
defmodule AgentRuntime.Llm.Plan.Steps.ExecutePromptStep do
  @behaviour AgentRuntime.Llm.Plan.Step

  alias AgentRuntime.Llm.Plan.PlanContext
  alias AgentRuntime.Llm.Executor

  @impl true
  def name, do: "execute_prompt"

  @impl true
  def run(%PlanContext{} = ctx, opts) do
    mode = Keyword.get(opts, :mode, :non_stream)

    final_messages = PlanContext.final_messages(ctx)
    input = normalize_input(ctx.input, final_messages)

    case mode do
      :stream ->
        on_chunk = Keyword.fetch!(opts, :on_chunk)
        # PASSTHROUGH: return Executor's result shape
        {:halt, Executor.execute_stream(ctx.profile, ctx.overrides, input, ctx.exec_meta, on_chunk)}

      _ ->
        # PASSTHROUGH: return Executor's result shape
        {:halt, Executor.execute(ctx.profile, ctx.overrides, input, ctx.exec_meta)}
    end
  end

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
