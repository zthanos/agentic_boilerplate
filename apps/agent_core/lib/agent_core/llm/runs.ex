defmodule AgentCore.Llm.Runs do
  @moduledoc "Public API for managing LLM runs."

  alias AgentCore.Llm.RunSnapshot

  defp store do
    Application.fetch_env!(:agent_core, __MODULE__)
    |> Keyword.fetch!(:store)
  end

  @spec put(RunSnapshot.t()) :: :ok | {:error, term()}
  def put(%RunSnapshot{} = snap) do
    case store().put(snap) do
      {:ok, _id} -> :ok
      {:error, e} -> {:error, e}
    end
  end

  @spec get_by_fingerprint(String.t()) :: {:ok, RunSnapshot.t()} | :error
  def get_by_fingerprint(fp) when is_binary(fp) do
    case store().get_by_fingerprint(fp) do
      {:ok, snap} -> {:ok, snap}
      {:error, :not_found} -> :error
      {:error, e} -> {:error, e}
    end
  end

  @spec list(keyword()) :: {:ok, [RunSnapshot.t()]} | {:error, term()}
  def list(opts \\ []), do: store().list(opts)


  def mark_started(fp), do: normalize_lifecycle(store().mark_started(fp))
  def mark_finished(fp, outcome), do: normalize_lifecycle(store().mark_finished(fp, outcome))
  def mark_failed(fp, reason, outcome), do: normalize_lifecycle(store().mark_failed(fp, reason, outcome))

  defp normalize_lifecycle({:ok, _id}), do: :ok
  defp normalize_lifecycle({:error, :not_found}), do: {:error, :not_found}
  defp normalize_lifecycle({:error, e}), do: {:error, e}
end
