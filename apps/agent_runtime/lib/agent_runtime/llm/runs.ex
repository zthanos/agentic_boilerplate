defmodule AgentRuntime.Llm.Runs do
  @moduledoc """
  Runtime façade for retrieving run snapshots.

  agent_web should call agent_runtime (not agent_core) to keep dependency direction clean.
  """

  alias AgentCore.Llm.RunSnapshot
  alias AgentCore.Llm.Runs, as: CoreRuns

  @spec list(keyword()) :: {:ok, [RunSnapshot.t()]} | {:error, term()}
  def list(opts \\ []) when is_list(opts), do: CoreRuns.list(opts)

  @spec get(String.t()) :: {:ok, RunSnapshot.t()} | {:error, :not_found} | {:error, term()}
  def get(run_id) when is_binary(run_id), do: CoreRuns.get(run_id)

end
