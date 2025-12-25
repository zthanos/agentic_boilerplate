defmodule AgentCore.Llm.RunStore do
  @moduledoc """
  Storage abstraction for LLM Runs.
  """

  alias AgentCore.Llm.RunSnapshot

  @type error :: term()
  @type outcome :: map()

  @type run_id :: Ecto.UUID.t()
  @type trace_id :: Ecto.UUID.t()

  @callback put(RunSnapshot.t()) :: {:ok, run_id()} | {:error, error()}
  @callback get(run_id()) :: {:ok, RunSnapshot.t()} | {:error, :not_found} | {:error, error()}

  # Query surface: keep it as list/1 with filters to avoid API sprawl
  # Supported filters: trace_id, fingerprint, profile_id, status, limit, order
  @callback list(keyword()) :: {:ok, [RunSnapshot.t()]} | {:error, error()}

  # Lifecycle
  @callback mark_started(run_id()) :: {:ok, run_id()} | {:error, :not_found} | {:error, error()}
  @callback mark_finished(run_id(), outcome()) :: {:ok, run_id()} | {:error, :not_found} | {:error, error()}
  @callback mark_failed(run_id(), error(), outcome()) :: {:ok, run_id()} | {:error, :not_found} | {:error, error()}
end
