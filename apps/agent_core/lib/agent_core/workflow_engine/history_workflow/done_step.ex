defmodule AgentCore.WorkflowEngine.HistoryWorkflow.DoneStep do
  @moduledoc """
  Final step to complete the history workflow and format the output.

  This step finalizes the workflow execution by collecting the results from
  previous steps and formatting them into the expected output structure.
  It serves as the exit node for the history workflow.

  ## Input

  Expects context artifacts from previous steps:
  - `ctx.artifacts[:history_context]` - The formatted context string (may be nil)
  - `ctx.artifacts[:history_items_used]` - Count of history items used

  ## Output

  Returns the final workflow output with:
  - `history_context` - The formatted context string or nil
  - `history_items_used` - Number of history items included

  ## Validation

  Performs basic validation to ensure the output meets the expected contract:
  - history_context is either a string or nil
  - history_items_used is a non-negative integer
  """

  @behaviour AgentCore.WorkflowEngine.Step

  @impl true
  def id, do: :done

  @impl true
  def run(ctx, _input, _opts) do
    # Extract results from context
    history_context = AgentCore.WorkflowEngine.Context.get_artifact(ctx, :history_context)

    history_items_used =
      AgentCore.WorkflowEngine.Context.get_artifact(ctx, :history_items_used) || 0

    # Validate the results
    case validate_output(history_context, history_items_used) do
      :ok ->
        # Create the final output
        final_output = %{
          history_context: history_context,
          history_items_used: history_items_used
        }

        # Store the final output in artifacts for workflow result
        updated_ctx =
          AgentCore.WorkflowEngine.Context.put_artifact(ctx, :final_output, final_output)

        output = %{
          workflow_completed: true,
          has_history_context: not is_nil(history_context),
          items_used: history_items_used,
          context_length:
            if(is_binary(history_context), do: String.length(history_context), else: 0)
        }

        {:ok, updated_ctx, output}

      {:error, reason} ->
        {:error, ctx, %{validation_error: reason, step: :done}}
    end
  end

  # Private function to validate the output
  defp validate_output(history_context, history_items_used) do
    cond do
      not (is_nil(history_context) or is_binary(history_context)) ->
        {:error, "history_context must be a string or nil"}

      not is_integer(history_items_used) ->
        {:error, "history_items_used must be an integer"}

      history_items_used < 0 ->
        {:error, "history_items_used must be non-negative"}

      # If we have a context, we should have used at least one item
      is_binary(history_context) and String.length(history_context) > 0 and
          history_items_used == 0 ->
        {:error, "inconsistent state: have context but items_used is 0"}

      # If we have no context, items_used should be 0
      is_nil(history_context) and history_items_used > 0 ->
        {:error, "inconsistent state: no context but items_used > 0"}

      true ->
        :ok
    end
  end
end
