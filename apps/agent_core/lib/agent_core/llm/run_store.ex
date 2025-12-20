defmodule AgentCore.Llm.RunStore do
  @moduledoc """
  Storage abstraction for LLM Runs.

  This is the only API the rest of the system uses.
  """

  alias AgentCore.Llm.RunSnapshot

  @type id :: term()
  @type error :: term()

  @callback put(RunSnapshot.t()) :: {:ok, id()} | {:error, error()}
  @callback get_by_fingerprint(String.t()) :: {:ok, RunSnapshot.t()} | {:error, :not_found} | {:error, error()}
  @callback list(keyword()) :: {:ok, [RunSnapshot.t()]} | {:error, error()}
end
