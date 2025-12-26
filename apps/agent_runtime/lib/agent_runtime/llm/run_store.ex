defmodule AgentRuntime.Llm.RunStore do
  @moduledoc false



  @spec impl() :: module()
  def impl do
    Application.get_env(:agent_runtime, __MODULE__, [])
    |> Keyword.get(:impl, AgentCore.Llm.RunStore.Ecto)
  end

  @spec put(AgentCore.Llm.RunSnapshot.t()) :: {:ok, binary()} | {:error, term()}
  def put(snap), do: impl().put(snap)

  @spec mark_started(binary()) :: {:ok, binary()} | {:error, term()}
  def mark_started(fp), do: impl().mark_started(fp)

  @spec mark_finished(binary(), map()) :: {:ok, binary()} | {:error, term()}
  def mark_finished(fp, outcome \\ %{}), do: impl().mark_finished(fp, outcome)

  @spec mark_failed(binary(), term(), map()) :: {:ok, binary()} | {:error, term()}
  def mark_failed(fp, error, outcome \\ %{}), do: impl().mark_failed(fp, error, outcome)
end
