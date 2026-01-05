defmodule AgentCore.WorkflowEngine.RagConversationWorkflow.FinalResponseStep do
  @moduledoc """
  Step to generate final LLM responses with real-time token streaming.

  This step generates responses using the LLM with token-by-token streaming
  for real-time UI updates. It handles both streaming and non-streaming modes
  based on whether the on_chunk callback is provided.
  """

  @behaviour AgentCore.WorkflowEngine.Step

  require Logger
  alias AgentCore.Providers.Response

  @impl true
  def id, do: :final_response

  @impl true
  def run(ctx, input, opts) do
    enhanced_prompt = AgentCore.WorkflowEngine.Context.get_artifact(ctx, :enhanced_prompt)
    user_message = Map.get(input, :user_message, "")
    profile = Map.get(input, :profile)
    overrides = Map.get(input, :overrides, %{})
    on_chunk = Map.get(input, :on_chunk)

    # Normalize user_message to handle nil values
    normalized_user_message = if is_binary(user_message), do: user_message, else: ""

    # Decide whether to use streaming based on callback availability
    use_streaming = is_function(on_chunk, 1)

    case generate_final_response(
           enhanced_prompt,
           normalized_user_message,
           profile,
           overrides,
           on_chunk,
           use_streaming,
           opts
         ) do
      {:ok, response, response_metadata} ->
        updated_ctx =
          ctx
          |> AgentCore.WorkflowEngine.Context.put_artifact(:final_response, response)
          |> AgentCore.WorkflowEngine.Context.put_artifact(:response_metadata, response_metadata)

        output = %{
          response_generated: true,
          response_length: String.length(response),
          enhanced_prompt_length: String.length(enhanced_prompt || ""),
          original_message_length: String.length(normalized_user_message),
          generation_metadata: response_metadata,
          streaming_used: use_streaming
        }

        {:ok, updated_ctx, output}

      {:error, reason} ->
        Logger.warning("[workflow] final_response generation failed: #{inspect(reason)}")

        # Generate fallback response on error
        fallback_response = generate_fallback_response(normalized_user_message, reason, opts)

        # Stream the fallback response if callback is available
        if is_function(on_chunk, 1) do
          on_chunk.(fallback_response)
        end

        response_metadata = %{
          fallback_used: true,
          error: reason,
          generation_time: DateTime.utc_now()
        }

        updated_ctx =
          ctx
          |> AgentCore.WorkflowEngine.Context.put_artifact(:final_response, fallback_response)
          |> AgentCore.WorkflowEngine.Context.put_artifact(:response_metadata, response_metadata)

        output = %{
          response_generated: true,
          fallback_used: true,
          error: reason,
          response_length: String.length(fallback_response),
          enhanced_prompt_length: String.length(enhanced_prompt || ""),
          original_message_length: String.length(normalized_user_message),
          generation_metadata: response_metadata
        }

        {:ok, updated_ctx, output}
    end
  end

  # Generate final response with streaming support
  defp generate_final_response(
         enhanced_prompt,
         user_message,
         profile,
         overrides,
         on_chunk,
         use_streaming,
         opts
       )
       when not is_nil(profile) do
    # Validate enhanced prompt is available
    if is_nil(enhanced_prompt) or String.trim(enhanced_prompt) == "" do
      {:error, "no_enhanced_prompt"}
    else
      # Get system prompt from options or use default
      system_prompt = get_system_prompt(opts)

      # Build LLM input for response generation
      llm_input = %{
        type: :chat,
        messages: [
          %{role: :system, content: system_prompt},
          %{role: :user, content: enhanced_prompt}
        ]
      }

      # Build execution metadata
      exec_meta = %{
        "phase" => "generate_final_response",
        "original_message_length" => String.length(user_message),
        "enhanced_prompt_length" => String.length(enhanced_prompt)
      }

      # Configure response generation overrides
      response_overrides = build_response_overrides(overrides, opts)

      # Record generation start time
      start_time = System.monotonic_time(:millisecond)

      # Choose streaming or non-streaming execution
      result =
        if use_streaming do
          execute_with_streaming(profile, response_overrides, llm_input, exec_meta, on_chunk)
        else
          execute_without_streaming(profile, response_overrides, llm_input, exec_meta)
        end

      case result do
        {:ok, response_text, token_usage} ->
          end_time = System.monotonic_time(:millisecond)
          generation_time_ms = end_time - start_time

          response_metadata = %{
            generation_time_ms: generation_time_ms,
            generation_time: DateTime.utc_now(),
            token_usage: token_usage,
            enhanced_prompt_used: true,
            fallback_used: false,
            streaming_used: use_streaming
          }

          # Format and validate the response
          formatted_response = format_response(response_text, opts)

          {:ok, formatted_response, response_metadata}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp generate_final_response(
         _enhanced_prompt,
         _user_message,
         _profile,
         _overrides,
         _on_chunk,
         _use_streaming,
         _opts
       ) do
    {:error, "no_profile"}
  end

  # Execute LLM with token streaming
  defp execute_with_streaming(profile, overrides, llm_input, exec_meta, on_chunk) do
    Logger.info("[FinalResponseStep] Starting streaming execution")

    # Use the streaming executor
    case AgentRuntime.Llm.Executor.execute_stream(
           profile,
           overrides,
           llm_input,
           exec_meta,
           on_chunk
         ) do
      {:ok, %{response: response}} ->
        # Extract the full response text and token usage
        case Response.content(response) do
          text when is_binary(text) and text != "" ->
            token_usage = extract_token_usage(response)
            {:ok, text, token_usage}

          _ ->
            {:error, "empty_or_invalid_response"}
        end

      {:error, reason} ->
        Logger.error("[FinalResponseStep] Streaming execution failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Execute LLM without streaming (standard execution)
  defp execute_without_streaming(profile, overrides, llm_input, exec_meta) do
    Logger.info("[FinalResponseStep] Starting non-streaming execution")

    case AgentRuntime.Llm.Executor.execute(profile, overrides, llm_input, exec_meta) do
      {:ok, %{response: response}} ->
        case Response.content(response) do
          text when is_binary(text) and text != "" ->
            token_usage = extract_token_usage(response)
            {:ok, text, token_usage}

          _ ->
            {:error, "empty_or_invalid_response"}
        end

      {:error, reason} ->
        Logger.error("[FinalResponseStep] Non-streaming execution failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Build response generation overrides with appropriate settings
  defp build_response_overrides(base_overrides, opts) do
    # Default response generation settings
    default_overrides = %{
      "generation" => %{
        "temperature" => Map.get(opts, :temperature, 0.7),
        "max_tokens" => Map.get(opts, :max_tokens, 2000)
      },
      "budgets" => %{
        "request_timeout_ms" => Map.get(opts, :request_timeout_ms, 15_000),
        "max_retries" => Map.get(opts, :max_retries, 2)
      }
    }

    # Merge with provided overrides, giving precedence to provided values
    deep_merge(default_overrides, base_overrides)
  end

  # Deep merge two maps, giving precedence to the second map
  defp deep_merge(map1, map2) when is_map(map1) and is_map(map2) do
    Map.merge(map1, map2, fn _key, v1, v2 ->
      if is_map(v1) and is_map(v2) do
        deep_merge(v1, v2)
      else
        v2
      end
    end)
  end

  defp deep_merge(_map1, map2), do: map2

  # Format the response text
  defp format_response(text, opts) do
    # Apply any response formatting options
    formatted =
      text
      |> String.trim()
      |> apply_length_limits(opts)
      |> apply_content_filters(opts)

    formatted
  end

  # Apply length limits to response if configured
  defp apply_length_limits(text, opts) do
    case Map.get(opts, :max_response_length) do
      max_length when is_integer(max_length) and max_length > 0 ->
        if String.length(text) > max_length do
          truncated = String.slice(text, 0, max_length - 3)
          "#{truncated}..."
        else
          text
        end

      _ ->
        text
    end
  end

  # Apply content filters if configured
  defp apply_content_filters(text, opts) do
    # Apply any content filtering rules from options
    filters = Map.get(opts, :content_filters, [])

    Enum.reduce(filters, text, fn filter, acc ->
      apply_content_filter(acc, filter)
    end)
  end

  # Apply a single content filter
  defp apply_content_filter(text, {:remove_pattern, pattern}) when is_binary(pattern) do
    String.replace(text, pattern, "")
  end

  defp apply_content_filter(text, {:replace_pattern, pattern, replacement})
       when is_binary(pattern) and is_binary(replacement) do
    String.replace(text, pattern, replacement)
  end

  defp apply_content_filter(text, _unknown_filter), do: text

  # Generate fallback response when LLM generation fails
  defp generate_fallback_response(user_message, error_reason, opts) do
    fallback_template = Map.get(opts, :fallback_template, default_fallback_template())

    # Replace placeholders in fallback template
    fallback_response =
      fallback_template
      |> String.replace("{user_message}", String.slice(user_message, 0, 100))
      |> String.replace("{error_reason}", format_error_reason(error_reason))
      |> String.replace("{timestamp}", DateTime.to_string(DateTime.utc_now()))

    # Apply content filters to fallback response as well
    apply_content_filters(fallback_response, opts)
  end

  # Format error reason for user-friendly display
  defp format_error_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_error_reason(reason) when is_binary(reason), do: reason
  defp format_error_reason(_reason), do: "system_error"

  # Extract token usage information from LLM response
  defp extract_token_usage(response) do
    # Try to extract token usage from response metadata
    case response do
      %{metadata: %{token_usage: usage}} -> usage
      %{token_usage: usage} -> usage
      %{usage: usage} -> usage
      _ -> %{}
    end
  end

  # Get system prompt for response generation
  defp get_system_prompt(opts) do
    Map.get(opts, :system_prompt, default_system_prompt())
  end

  # Default system prompt for response generation
  defp default_system_prompt do
    """
    You are a helpful AI assistant. You have been provided with a user message that may include relevant historical context from previous conversations.

    Please provide a helpful, accurate, and contextually appropriate response to the user's message. Use the historical context when relevant, but focus primarily on addressing the current user's needs.

    Guidelines:
    - Be helpful, accurate, and concise
    - Use historical context when it adds value to your response
    - If historical context seems irrelevant or conflicting, focus on the current message
    - Maintain a conversational and friendly tone
    - Provide actionable information when possible
    - If you're unsure about something, acknowledge the uncertainty

    Respond directly to the user's message using the provided context appropriately.
    """
  end

  # Default fallback template when LLM generation fails
  defp default_fallback_template do
    """
    I apologize, but I'm currently experiencing technical difficulties generating a response to your message.

    Your message: "{user_message}"

    Please try rephrasing your question or try again in a moment. If the issue persists, please contact support.

    Error details: {error_reason}
    Time: {timestamp}
    """
  end
end
