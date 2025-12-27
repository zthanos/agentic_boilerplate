# lib/agent_runtime/llm/plan/plan_context.ex
defmodule AgentRuntime.Llm.Plan.PlanContext do
  @moduledoc """
  Mutable context passed through plan steps.

  Goal: produce a final input (messages) or a clarification question,
  then hand off to the existing Executor.
  """

  @enforce_keys [:profile, :overrides, :input, :exec_meta]
  defstruct [
    :profile,
    :overrides,
    :input,
    :exec_meta,

    # Decisions / intermediate data
    decisions: %{
      needs_history: false,
      history_query: nil,
      needs_clarification: false,
      clarification_question: nil
    },

    # Context augmentation (memory injection, etc.)
    augmented_messages: nil,

    # Debug trail for audits (optional)
    debug: []
  ]

  @type t :: %__MODULE__{
          profile: term(),
          overrides: map(),
          input: map(),
          exec_meta: map(),
          decisions: map(),
          augmented_messages: list(map()) | nil,
          debug: list(map())
        }

  def add_debug(%__MODULE__{} = ctx, step, data) when is_binary(step) and is_map(data) do
    %{ctx | debug: ctx.debug ++ [%{step: step, data: data}]}
  end

  def put_decision(%__MODULE__{} = ctx, key, val) do
    %{ctx | decisions: Map.put(ctx.decisions || %{}, key, val)}
  end

  def get_messages(%__MODULE__{} = ctx) do
    get_in(ctx.input, ["messages"]) || get_in(ctx.input, [:messages]) || []
  end

  def set_augmented_messages(%__MODULE__{} = ctx, msgs) when is_list(msgs) do
    %{ctx | augmented_messages: msgs}
  end

  def final_messages(%__MODULE__{} = ctx) do
    case ctx.augmented_messages do
      msgs when is_list(msgs) -> msgs
      _ -> get_messages(ctx)
    end
  end
end
