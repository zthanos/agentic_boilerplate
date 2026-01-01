defmodule AgentCore.WorkflowEngine.Step do
  @moduledoc """
  Behavior for implementing workflow steps.

  A step represents a single unit of work within a workflow. Each step must implement
  the `id/0` and `run/3` callbacks to provide identification and execution logic.

  ## Key Principles

  - All state changes flow through the immutable `ctx` parameter
  - `output` is always structured data for observability
  - `opts` provides per-node configuration without affecting flow logic
  - Steps are pure functions with no side effects on global state

  ## Example Implementation

      defmodule MyApp.Steps.ProcessDataStep do
        @behaviour AgentCore.WorkflowEngine.Step

        @impl true
        def id, do: :process_data

        @impl true
        def run(ctx, input, opts) do
          case process_input(input, opts) do
            {:ok, result} ->
              updated_ctx = put_in(ctx.artifacts[:processed_data], result)
              {:ok, updated_ctx, %{status: :processed, items: length(result)}}

            {:error, reason} ->
              {:error, ctx, %{error: reason, step: :process_data}}
          end
        end

        defp process_input(input, opts) do
          # Implementation details...
        end
      end

  ## Return Values

  Steps must return one of three tuples:

  - `{:ok, ctx, output}` - Successful execution with updated context and output
  - `{:skip, ctx, output}` - Step was skipped but execution should continue
  - `{:error, ctx, error}` - Step failed and workflow should terminate
  """

  @doc """
  Returns a unique identifier for this step.

  The identifier is used for workflow specification, tracing, and debugging.
  It should be an atom or string that uniquely identifies the step type.

  ## Examples

      iex> MyStep.id()
      :my_step

      iex> AnotherStep.id()
      "complex_processing_step"
  """
  @callback id() :: atom() | String.t()

  @doc """
  Executes the step with the given context, input, and options.

  ## Parameters

  - `ctx` - The workflow runtime context containing decisions, artifacts, debug info, etc.
  - `input` - Input data for this step, typically from previous steps or workflow input
  - `opts` - Per-node configuration options from the workflow specification

  ## Return Values

  - `{:ok, ctx, output}` - Step executed successfully
  - `{:skip, ctx, output}` - Step was skipped (e.g., due to conditions)
  - `{:error, ctx, error}` - Step failed and workflow should terminate

  The `ctx` parameter must be treated as immutable. Any changes should be made
  by updating the context and returning the new version.

  The `output` should be structured data that provides observability into what
  the step accomplished. This data is used for tracing and debugging.

  ## Examples

      # Successful execution
      def run(ctx, %{data: data}, opts) do
        processed = process_data(data, opts)
        updated_ctx = put_in(ctx.artifacts[:result], processed)
        {:ok, updated_ctx, %{processed_items: length(processed)}}
      end

      # Conditional skip
      def run(ctx, input, _opts) do
        if should_skip?(input) do
          {:skip, ctx, %{reason: :condition_not_met}}
        else
          # ... normal processing
        end
      end

      # Error handling
      def run(ctx, input, _opts) do
        case validate_input(input) do
          :ok ->
            # ... process input
          {:error, reason} ->
            {:error, ctx, %{validation_error: reason}}
        end
      end
  """
  @callback run(ctx :: map(), input :: map(), opts :: map()) ::
              {:ok, map(), map()} | {:skip, map(), map()} | {:error, map(), map()}
end
