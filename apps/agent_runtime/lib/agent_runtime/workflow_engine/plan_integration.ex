# defmodule AgentRuntime.WorkflowEngine.PlanIntegration do
#   @moduledoc """
#   Integration layer between the workflow engine and existing plan system.

#   This module provides utilities for running workflows within plan contexts,
#   handling result transformation, and ensuring backward compatibility with
#   existing plan semantics.
#   """

#   alias AgentCore.WorkflowEngine.{Registry, Runtime, Context}
#   alias AgentRuntime.Llm.Plan.PlanContext

#   @type workflow_id :: atom() | String.t()
#   @type plan_context :: PlanContext.t()
#   @type workflow_result :: {:ok, map()} | {:error, term()}

#   @doc """
#   Executes a workflow within a plan context.

#   This function:
#   1. Retrieves the workflow specification from the registry
#   2. Converts plan context to workflow input format
#   3. Executes the workflow using the runtime engine
#   4. Transforms workflow results back to plan context format
#   5. Handles errors and propagates them appropriately

#   ## Parameters

#   - `plan_ctx`: The current plan context
#   - `workflow_id`: The ID of the workflow to execute
#   - `opts`: Optional configuration (default: %{})

#   ## Returns

#   - `{:ok, result}`: Successful execution with workflow output
#   - `{:error, reason}`: Execution failure with error details

#   ## Examples

#       iex> plan_ctx = %PlanContext{input: %{"messages" => [...]}, ...}
#       iex> PlanIntegration.run_workflow(plan_ctx, :history_rag)
#       {:ok, %{history_context: "...", history_items_used: 3}}

#       iex> PlanIntegration.run_workflow(plan_ctx, :nonexistent)
#       {:error, "Workflow not found"}
#   """
#   @spec run_workflow(plan_context(), workflow_id(), map()) :: workflow_result()
#   def run_workflow(%PlanContext{} = plan_ctx, workflow_id, opts \\ %{}) do
#     with {:ok, spec} <- Registry.get_workflow(workflow_id),
#          {:ok, workflow_input} <- convert_plan_to_workflow_input(plan_ctx, opts),
#          {:ok, result} <- Runtime.execute(spec, workflow_input, opts) do
#       {:ok, extract_workflow_output(result)}
#     else
#       {:error, %{error: error}} ->
#         # Workflow execution failed - extract error from WorkflowResult
#         {:error, error}

#       {:error, reason} ->
#         # Registry or conversion error
#         {:error, reason}
#     end
#   end

#   @doc """
#   Executes a workflow and updates the plan context with results.

#   This is a convenience function that combines workflow execution with
#   plan context updates, maintaining existing plan semantics.

#   ## Parameters

#   - `plan_ctx`: The current plan context
#   - `workflow_id`: The ID of the workflow to execute
#   - `opts`: Optional configuration

#   ## Returns

#   - `{:cont, updated_plan_ctx}`: Successful execution with updated context
#   - `{:halt, {:error, reason}}`: Execution failure

#   ## Examples

#       iex> plan_ctx = %PlanContext{...}
#       iex> PlanIntegration.run_workflow_with_context_update(plan_ctx, :history_rag)
#       {:cont, %PlanContext{decisions: %{history_context: "..."}}}
#   """
#   @spec run_workflow_with_context_update(plan_context(), workflow_id(), map()) ::
#           {:cont, plan_context()} | {:halt, {:error, term()}}
#   def run_workflow_with_context_update(%PlanContext{} = plan_ctx, workflow_id, opts \\ %{}) do
#     case run_workflow(plan_ctx, workflow_id, opts) do
#       {:ok, workflow_output} ->
#         updated_ctx =
#           apply_workflow_results_to_plan_context(plan_ctx, workflow_output, workflow_id)

#         {:cont, updated_ctx}

#       {:error, reason} ->
#         {:halt, {:error, reason}}
#     end
#   end

#   @doc """
#   Converts a plan context to workflow input format.

#   Extracts relevant data from the plan context and formats it for workflow execution.
#   The conversion focuses on the current message and conversation metadata.

#   ## Parameters

#   - `plan_ctx`: The plan context to convert
#   - `opts`: Optional conversion options

#   ## Returns

#   - `{:ok, workflow_input}`: Successfully converted input
#   - `{:error, reason}`: Conversion failure
#   """
#   @spec convert_plan_to_workflow_input(plan_context(), map()) ::
#           {:ok, map()} | {:error, String.t()}
#   def convert_plan_to_workflow_input(%PlanContext{} = plan_ctx, _opts \\ %{}) do
#     messages = PlanContext.get_messages(plan_ctx)

#     # Extract the last user message as current_message
#     current_message =
#       messages
#       |> Enum.reverse()
#       |> Enum.find_value("", fn msg ->
#         case msg do
#           %{"role" => "user", "content" => content} when is_binary(content) -> content
#           %{role: :user, content: content} when is_binary(content) -> content
#           _ -> nil
#         end
#       end)

#     # Extract conversation_id from exec_meta
#     conversation_id = get_in(plan_ctx.exec_meta, ["conversation_id"])

#     workflow_input = %{
#       current_message: current_message,
#       conversation_id: conversation_id
#     }

#     {:ok, workflow_input}
#   end

#   @doc """
#   Extracts the final output from a workflow result.

#   Normalizes the workflow result structure to provide a consistent
#   output format for plan integration.

#   ## Parameters

#   - `workflow_result`: The WorkflowResult struct from runtime execution

#   ## Returns

#   - `map()`: Normalized workflow output
#   """
#   @spec extract_workflow_output(map()) :: map()
#   def extract_workflow_output(%{final_output: final_output}) when is_map(final_output) do
#     final_output
#   end

#   def extract_workflow_output(%{final_output: nil}) do
#     %{}
#   end

#   def extract_workflow_output(_result) do
#     %{}
#   end

#   @doc """
#   Applies workflow results to a plan context.

#   Updates the plan context with workflow outputs, maintaining compatibility
#   with existing plan step expectations. This includes updating decisions
#   and adding debug information.

#   ## Parameters

#   - `plan_ctx`: The original plan context
#   - `workflow_output`: The output from workflow execution
#   - `workflow_id`: The ID of the executed workflow

#   ## Returns

#   - `plan_context()`: Updated plan context with workflow results
#   """
#   @spec apply_workflow_results_to_plan_context(plan_context(), map(), workflow_id()) ::
#           plan_context()
#   def apply_workflow_results_to_plan_context(
#         %PlanContext{} = plan_ctx,
#         workflow_output,
#         workflow_id
#       ) do
#     plan_ctx
#     |> update_plan_decisions_from_workflow(workflow_output)
#     |> add_workflow_debug_info(workflow_output, workflow_id)
#   end

#   # Private Functions

#   defp update_plan_decisions_from_workflow(%PlanContext{} = plan_ctx, workflow_output) do
#     # Handle history workflow specific outputs
#     case workflow_output do
#       %{history_context: history_context, history_items_used: items_used} ->
#         plan_ctx
#         |> PlanContext.put_decision(:needs_history, not is_nil(history_context))
#         |> PlanContext.put_decision(:history_context, history_context)
#         |> PlanContext.put_decision(:history_items_used, items_used)

#       %{history_context: history_context} ->
#         plan_ctx
#         |> PlanContext.put_decision(:needs_history, not is_nil(history_context))
#         |> PlanContext.put_decision(:history_context, history_context)
#         |> PlanContext.put_decision(:history_items_used, 0)

#       _ ->
#         # For other workflow types, preserve existing behavior
#         plan_ctx
#     end
#   end

#   defp add_workflow_debug_info(%PlanContext{} = plan_ctx, workflow_output, workflow_id) do
#     debug_data = %{
#       "workflow_id" => workflow_id,
#       "workflow_output" => workflow_output,
#       "executed_via" => "WorkflowEngine.PlanIntegration"
#     }

#     PlanContext.add_debug(plan_ctx, "workflow_execution", debug_data)
#   end
# end
