defmodule AgentCore.Llm.RunStore.Memory do
  @behaviour AgentCore.Llm.RunStore
  alias AgentCore.Llm.RunSnapshot

  @table __MODULE__

  def start_link do
    :ets.new(@table, [:named_table, :public, read_concurrency: true])
    {:ok, self()}
  end

  @impl true
  def put(%RunSnapshot{} = snap) do
    :ets.insert(@table, {snap.fingerprint, snap})
    {:ok, snap.fingerprint}
  end

  @impl true
  def get_by_fingerprint(fp) do
    case :ets.lookup(@table, fp) do
      [{^fp, snap}] -> {:ok, snap}
      [] -> {:error, :not_found}
    end
  end

  @impl true
  def list(_opts), do: {:ok, :ets.tab2list(@table) |> Enum.map(fn {_k, v} -> v end)}
end
