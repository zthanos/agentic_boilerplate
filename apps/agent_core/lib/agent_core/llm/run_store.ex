defmodule AgentCore.Llm.RunStore do
  @moduledoc """
  Storage abstraction for LLM Runs.

  This is the only API the rest of the system uses.
  """

  alias AgentCore.Llm.RunSnapshot

  @type id :: term()
  @type error :: term()
  @type outcome :: map()

  @callback put(RunSnapshot.t()) :: {:ok, id()} | {:error, error()}
  @callback get_by_fingerprint(String.t()) ::
              {:ok, RunSnapshot.t()} | {:error, :not_found} | {:error, error()}
  @callback list(keyword()) :: {:ok, [RunSnapshot.t()]} | {:error, error()}

  # Lifecycle callbacks (runtime-driven)
  @callback mark_started(String.t()) :: {:ok, id()} | {:error, :not_found} | {:error, error()}
  @callback mark_finished(String.t(), outcome()) ::
              {:ok, id()} | {:error, :not_found} | {:error, error()}
  @callback mark_failed(String.t(), error(), outcome()) ::
              {:ok, id()} | {:error, :not_found} | {:error, error()}
end
