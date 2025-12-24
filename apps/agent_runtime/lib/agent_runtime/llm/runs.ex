defmodule AgentRuntime.Llm.Runs do
  @moduledoc """
  Runtime façade for retrieving run snapshots.

  agent_web should call agent_runtime (not agent_core) to keep dependency direction clean.
  """

  alias AgentCore.Llm.Runs

  def list(opts \\ []) when is_list(opts), do: Runs.list(opts)

  def get_by_fingerprint(fp) when is_binary(fp), do: Runs.get_by_fingerprint(fp)
end
