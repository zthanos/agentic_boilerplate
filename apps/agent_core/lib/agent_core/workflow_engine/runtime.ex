defmodule AgentCore.WorkflowEngine.Runtime do
  @moduledoc """
  Generic execution engine for workflow specifications.

  The Runtime module provides the core execution logic for workflows, including:
  - Node traversal and execution
  - Edge predicate evaluation
  - Deterministic edge resolution
  - Execution tracing and observability
  - Error handling and propagation

  ## Usage

      # Execute a workflow
      spec = %AgentCore.WorkflowEngine.Spec{...}
      input = %{data: "input"}

      case AgentCore.WorkflowEngine.Runtime.execute(spec, input) do
        {:ok, result} ->
          # Handle successful execution
          IO.inspect(result.final_output)

        {:error, result} ->
          # Handle execution failure
          IO.inspect(result.error)
      end

  ## Execution Flow

  1. Validate workflow specification
  2. Initialize runtime context with input
  3. Start execution from entry node
  4. For each node:
     - Execute step with current context
     - Record execution trace
     - Evaluate outgoing edges
     - Select next node deterministically
  5. Continue until exit node or error
  6. Return WorkflowResult with status and trace

  ## Edge Resolution

  When multiple edges match from a node, the first matching edge in declaration
  order is selected. This ensures deterministic execution behavior.

  ## Error Handling

  The runtime implements fail-fast semantics:
  - Step errors terminate execution immediately
  - Unresolved transitions (no matching edges) cause failure
  - All errors include complete execution trace for debugging
  """

  alias AgentCore.WorkflowEngine.{Context, Spec, WorkflowResult}

  @doc """
  Executes a workflow specification with the given input.

  ## Parameters

  - `spec` - The workflow specification to execute
  - `input` - Input data for the workflow
  - `opts` - Optional execution options (default: %{})

  ## Options

  - `:timeout` - Maximum execution time in milliseconds
  - `:max_steps` - Maximum number of steps to prevent infinite loops
  - `:trace_level` - Level of tracing detail (:minimal, :normal, :verbose)

  ## Returns

  - `{:ok, WorkflowResult.t()}` - Successful execution
  - `{:error, WorkflowResult.t()}` - Failed execution with error details

  ## Examples

      iex> spec = %AgentCore.WorkflowEngine.Spec{...}
      iex> {:ok, result} = AgentCore.WorkflowEngine.Runtime.execute(spec, %{data: "test"})
      iex> result.status
      :ok
  """
  @spec execute(Spec.t(), map(), map()) ::
          {:ok, WorkflowResult.t()} | {:error, WorkflowResult.t()}
  def execute(%Spec{} = spec, input, opts \\ %{}) do
    require Logger
    Logger.info("[WorkflowRuntime] Starting execution for workflow_id=#{spec.id}")
    Logger.debug("[WorkflowRuntime] Input keys: #{inspect(Map.keys(input))}")

    with :ok <- Spec.validate(spec) do
      Logger.info("[WorkflowRuntime] Workflow spec validated successfully")

      # Initialize execution state
      ctx =
        Context.new(%{
          run_id: generate_run_id(),
          trace_id: generate_trace_id(),
          workflow_id: spec.id,
          workflow_version: spec.version
        })

      Logger.info("[WorkflowRuntime] Starting execution from entry node: #{spec.entry}")

      # Start execution from entry node
      result = execute_workflow(spec, ctx, input, spec.entry, [], [], opts)

      Logger.info(
        "[WorkflowRuntime] Workflow execution completed with status: #{inspect(elem(result, 0))}"
      )

      result
    else
      {:error, validation_errors} ->
        Logger.error(
          "[WorkflowRuntime] Workflow validation failed: #{inspect(validation_errors)}"
        )

        error_result =
          WorkflowResult.error(%{
            type: :validation_error,
            errors: validation_errors
          })

        {:error, error_result}
    end
  end

  # Private execution functions

  defp execute_workflow(spec, ctx, input, current_node, visited_nodes, trace, opts) do
    # Check for infinite loop protection
    max_steps = Map.get(opts, :max_steps, 1000)

    if length(visited_nodes) >= max_steps do
      error_result =
        WorkflowResult.error(
          %{type: :max_steps_exceeded, max_steps: max_steps},
          visited_nodes,
          trace
        )

      {:error, error_result}
    end

    # Check if we've reached an exit node
    if MapSet.member?(spec.exits, current_node) do
      # Execute the exit node and return result
      execute_exit_node(spec, ctx, input, current_node, visited_nodes, trace)
    else
      # Execute current node and continue
      execute_node_and_continue(spec, ctx, input, current_node, visited_nodes, trace, opts)
    end
  end

  defp execute_exit_node(spec, ctx, input, exit_node, visited_nodes, trace) do
    case execute_single_node(spec, ctx, input, exit_node) do
      {:ok, updated_ctx, output, node_trace} ->
        final_visited = visited_nodes ++ [exit_node]
        final_trace = trace ++ [node_trace]

        # Extract final output from context artifacts or use step output
        final_output = extract_final_output(updated_ctx, output)

        result = WorkflowResult.success(final_output, final_visited, final_trace)
        {:ok, result}

      {:skip, updated_ctx, output, node_trace} ->
        final_visited = visited_nodes ++ [exit_node]
        final_trace = trace ++ [node_trace]

        final_output = extract_final_output(updated_ctx, output)

        result = WorkflowResult.success(final_output, final_visited, final_trace)
        {:ok, result}

      {:error, _ctx, error, node_trace} ->
        final_visited = visited_nodes ++ [exit_node]
        final_trace = trace ++ [node_trace]

        result = WorkflowResult.failure(error, final_visited, final_trace)
        {:error, result}
    end
  end

  defp execute_node_and_continue(spec, ctx, input, current_node, visited_nodes, trace, opts) do
    case execute_single_node(spec, ctx, input, current_node) do
      {:ok, updated_ctx, _output, node_trace} ->
        updated_visited = visited_nodes ++ [current_node]
        updated_trace = trace ++ [node_trace]

        # Find next node using edge resolution
        case resolve_next_node(spec, updated_ctx, current_node) do
          {:ok, next_node} ->
            execute_workflow(
              spec,
              updated_ctx,
              input,
              next_node,
              updated_visited,
              updated_trace,
              opts
            )

          {:error, reason} ->
            error_result =
              WorkflowResult.failure(
                %{type: :unresolved_transition, node: current_node, reason: reason},
                updated_visited,
                updated_trace
              )

            {:error, error_result}
        end

      {:skip, updated_ctx, _output, node_trace} ->
        updated_visited = visited_nodes ++ [current_node]
        updated_trace = trace ++ [node_trace]

        # Continue with next node even if current was skipped
        case resolve_next_node(spec, updated_ctx, current_node) do
          {:ok, next_node} ->
            execute_workflow(
              spec,
              updated_ctx,
              input,
              next_node,
              updated_visited,
              updated_trace,
              opts
            )

          {:error, reason} ->
            error_result =
              WorkflowResult.failure(
                %{type: :unresolved_transition, node: current_node, reason: reason},
                updated_visited,
                updated_trace
              )

            {:error, error_result}
        end

      {:error, _ctx, error, node_trace} ->
        updated_visited = visited_nodes ++ [current_node]
        updated_trace = trace ++ [node_trace]

        result = WorkflowResult.failure(error, updated_visited, updated_trace)
        {:error, result}
    end
  end

  defp execute_single_node(spec, ctx, input, node_id) do
    start_time = System.monotonic_time(:millisecond)

    # Send step start notification if streaming callback is available
    if on_chunk = Map.get(input, :on_chunk) do
      step_name = format_step_name(node_id)
      on_chunk.("🔄 Starting: #{step_name}")
    end

    case Map.get(spec.nodes, node_id) do
      nil ->
        {:error, ctx, %{type: :node_not_found, node: node_id},
         create_error_trace(node_id, :node_not_found, 0)}

      %{step: step_module, opts: step_opts} ->
        try do
          case step_module.run(ctx, input, step_opts) do
            {:ok, updated_ctx, output} ->
              duration = System.monotonic_time(:millisecond) - start_time

              # Send step completion notification if streaming callback is available
              if on_chunk = Map.get(input, :on_chunk) do
                step_name = format_step_name(node_id)
                on_chunk.("✅ Completed: #{step_name} (#{duration}ms)")
              end

              trace_entry =
                create_trace_entry(node_id, step_module, :ok, duration, input, output, nil)

              {:ok, updated_ctx, output, trace_entry}

            {:skip, updated_ctx, output} ->
              duration = System.monotonic_time(:millisecond) - start_time

              # Send step skip notification if streaming callback is available
              if on_chunk = Map.get(input, :on_chunk) do
                step_name = format_step_name(node_id)
                on_chunk.("⏭️ Skipped: #{step_name} (#{duration}ms)")
              end

              trace_entry =
                create_trace_entry(node_id, step_module, :skip, duration, input, output, nil)

              {:skip, updated_ctx, output, trace_entry}

            {:error, updated_ctx, error} ->
              duration = System.monotonic_time(:millisecond) - start_time

              # Send step error notification if streaming callback is available
              if on_chunk = Map.get(input, :on_chunk) do
                step_name = format_step_name(node_id)
                on_chunk.("❌ Failed: #{step_name} (#{duration}ms)")
              end

              trace_entry =
                create_trace_entry(node_id, step_module, :error, duration, input, error, error)

              {:error, updated_ctx, error, trace_entry}

            other ->
              duration = System.monotonic_time(:millisecond) - start_time
              error = %{type: :invalid_step_return, node: node_id, returned: other}

              # Send step error notification if streaming callback is available
              if on_chunk = Map.get(input, :on_chunk) do
                step_name = format_step_name(node_id)
                on_chunk.("❌ Invalid return: #{step_name} (#{duration}ms)")
              end

              trace_entry =
                create_trace_entry(node_id, step_module, :error, duration, input, %{}, error)

              {:error, ctx, error, trace_entry}
          end
        rescue
          exception ->
            duration = System.monotonic_time(:millisecond) - start_time

            error = %{
              type: :step_exception,
              node: node_id,
              exception: Exception.message(exception)
            }

            # Send step exception notification if streaming callback is available
            if on_chunk = Map.get(input, :on_chunk) do
              step_name = format_step_name(node_id)
              on_chunk.("💥 Exception: #{step_name} - #{Exception.message(exception)}")
            end

            trace_entry =
              create_trace_entry(node_id, step_module, :error, duration, input, %{}, error)

            {:error, ctx, error, trace_entry}
        end
    end
  end

  defp resolve_next_node(spec, ctx, current_node) do
    # Find all edges from current node
    outgoing_edges = Enum.filter(spec.edges, fn edge -> edge.from == current_node end)

    case outgoing_edges do
      [] ->
        {:error, :no_outgoing_edges}

      edges ->
        # Evaluate edges in declaration order and return first match
        case find_first_matching_edge(edges, ctx) do
          nil -> {:error, :no_matching_edges}
          edge -> {:ok, edge.to}
        end
    end
  end

  defp find_first_matching_edge(edges, ctx) do
    Enum.find(edges, fn edge ->
      evaluate_predicate(edge.when, ctx)
    end)
  end

  defp evaluate_predicate({:always}, _ctx), do: true

  defp evaluate_predicate({:decision, key, value}, ctx) do
    Context.get_decision(ctx, key) == value
  end

  defp evaluate_predicate({:artifact_present, key}, ctx) do
    Context.get_artifact(ctx, key) != nil
  end

  defp evaluate_predicate({:custom, predicate_fn}, ctx) when is_function(predicate_fn, 1) do
    try do
      predicate_fn.(ctx)
    rescue
      _ -> false
    end
  end

  defp evaluate_predicate(_predicate, _ctx), do: false

  defp create_trace_entry(node_id, step_module, status, duration_ms, input, output, error) do
    %{
      node_id: node_id,
      step_module: step_module,
      status: status,
      duration_ms: duration_ms,
      input_keys: extract_keys(input),
      output_keys: extract_keys(output),
      error: error
    }
  end

  defp create_error_trace(node_id, error_type, duration_ms) do
    %{
      node_id: node_id,
      step_module: nil,
      status: :error,
      duration_ms: duration_ms,
      input_keys: [],
      output_keys: [],
      error: %{type: error_type}
    }
  end

  defp extract_keys(data) when is_map(data), do: Map.keys(data)
  defp extract_keys(_), do: []

  defp extract_final_output(ctx, step_output) do
    # Try to get final output from context artifacts, fallback to step output
    case Context.get_artifact(ctx, :final_output) do
      nil -> step_output
      final_output -> final_output
    end
  end

  defp generate_run_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp generate_trace_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  defp format_step_name(node_id) do
    node_id
    |> to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
end
