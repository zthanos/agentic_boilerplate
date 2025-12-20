defmodule AgentCore.Llm.Runs do
  @moduledoc """
  Facade for persisting and retrieving LLM run snapshots.
  """

  alias AgentCore.Llm.{RunSnapshot}

  def put(%RunSnapshot{} = snap) do
    impl().put(snap)
  end

  def get_by_fingerprint(fp) when is_binary(fp) do
    impl().get_by_fingerprint(fp)
  end

  def list(opts \\ []) when is_list(opts) do
    impl().list(opts)
  end

  defp impl do
    Application.fetch_env!(:agent_core, __MODULE__)[:store]
  end
end
