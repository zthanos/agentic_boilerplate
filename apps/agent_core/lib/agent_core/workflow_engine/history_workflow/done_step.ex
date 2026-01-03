defmodule AgentCore.WorkflowEngine.HistoryWorkflow.DoneStep do
  @moduledoc """
  Final step to complete the history workflow and generate the agent response.

  This step finalizes the workflow execution by using the historical context
  to generate an appropriate response to the user's message. It uses an LLM
  to create the final response with the gathered context.

  ## Input

  Expects context artifacts from previous steps:
  - `ctx.artifacts[:history_context]` - The formatted context string (may be nil)
  - `ctx.artifacts[:history_items_used]` - Count of history items used
  - Input should contain:
    - `current_message` - The original user message
    - `profile` - LLM profile for response generation
    - `overrides` - LLM overrides
    - `on_chunk` - Streaming callback for response generation
    - `agent_system_prompt` - System prompt for the agent

  ## Output

  Returns the final workflow output with:
  - `response` - The generated response text
  - `history_context` - The formatted context string or nil
  - `history_items_used` - Number of history items included

  ## Response Generation

  Uses the LLM to generate a response that incorporates the historical context
  when available, or responds directly to the message when no context is needed.
  """

  @behaviour AgentCore.WorkflowEngine.Step

  @impl true
  def id, do: :done

  @impl true
  def run(ctx, input, _opts) do
    # Extract results from context
    history_context = AgentCore.WorkflowEngine.Context.get_artifact(ctx, :history_context)

    history_items_used =
      AgentCore.WorkflowEngine.Context.get_artifact(ctx, :history_items_used) || 0

    # Extract input parameters
    current_message = Map.get(input, :current_message, "")
    profile = Map.get(input, :profile)
    overrides = Map.get(input, :overrides, %{})
    on_chunk = Map.get(input, :on_chunk)
    agent_system_prompt = Map.get(input, :agent_system_prompt, "You are a helpful AI assistant.")

    # Validate the intermediate results
    case validate_output(history_context, history_items_used) do
      :ok ->
        # Generate the final response using LLM
        case generate_response(
               current_message,
               history_context,
               agent_system_prompt,
               profile,
               overrides,
               on_chunk
             ) do
          {:ok, response} ->
            # Create the final output
            final_output = %{
              response: response,
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
                if(is_binary(history_context), do: String.length(history_context), else: 0),
              response_generated: true
            }

            {:ok, updated_ctx, output}

          {:error, reason} ->
            {:error, ctx, %{llm_error: reason, step: :done}}
        end

      {:error, reason} ->
        {:error, ctx, %{validation_error: reason, step: :done}}
    end
  end

  # Generate the final response using LLM
  defp generate_response(
         current_message,
         history_context,
         system_prompt,
         profile,
         overrides,
         on_chunk
       ) do
    # Build the system prompt with context if available
    enhanced_system_prompt =
      if is_binary(history_context) and String.length(history_context) > 0 do
        """
        #{system_prompt}

        #{history_context}

        Use the above historical context to inform your response when relevant. If the context doesn't relate to the current message, respond normally without forcing connections to the historical information.
        """
      else
        system_prompt
      end

    # Build LLM input
    llm_input = %{
      type: :chat,
      messages: [
        %{
          role: :system,
          content: enhanced_system_prompt
        },
        %{
          role: :user,
          content: current_message
        }
      ]
    }

    # Build execution metadata
    exec_meta = %{
      "phase" => "generate_response"
    }

    # Execute LLM request with streaming if callback provided
    if is_function(on_chunk, 1) do
      case AgentRuntime.Llm.Executor.execute_stream(
             profile,
             overrides,
             llm_input,
             exec_meta,
             on_chunk
           ) do
        {:ok, %{response: response}} ->
          {:ok, response.output_text || ""}

        {:error, reason} ->
          {:error, reason}
      end
    else
      case AgentRuntime.Llm.Executor.execute(profile, overrides, llm_input, exec_meta) do
        {:ok, %{response: response}} ->
          {:ok, response.output_text || ""}

        {:error, reason} ->
          {:error, reason}
      end
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
