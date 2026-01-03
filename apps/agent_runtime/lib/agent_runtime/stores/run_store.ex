defmodule AgentRuntime.Stores.RunStore do
  @moduledoc """
  Runtime wrapper for run store behavior.

  This module delegates to the configured run store implementation,
  providing a consistent interface for the runtime layer while
  allowing the actual implementation to be configured.
  """

  @behaviour AgentCore.Stores.RunStore

  alias AgentCore.Runs

  @impl true
  def create(%Runs{} = run) do
    store_impl().create(run)
  end

  @impl true
  def get(run_id) do
    store_impl().get(run_id)
  end

  @impl true
  def update(run_id, updates) do
    store_impl().update(run_id, updates)
  end

  @impl true
  def delete(run_id) do
    store_impl().delete(run_id)
  end

  @impl true
  def list(opts \\ []) do
    store_impl().list(opts)
  end

  @impl true
  def mark_started(run_id) do
    store_impl().mark_started(run_id)
  end

  @impl true
  def mark_completed(run_id, outcome) do
    store_impl().mark_completed(run_id, outcome)
  end

  @impl true
  def mark_failed(run_id, error, outcome) do
    store_impl().mark_failed(run_id, error, outcome)
  end

  @impl true
  def count(opts \\ []) do
    store_impl().count(opts)
  end

  @impl true
  def latest_by_fingerprint(fingerprint) do
    store_impl().latest_by_fingerprint(fingerprint)
  end

  @impl true
  def list_by_trace(trace_id, opts \\ []) do
    store_impl().list_by_trace(trace_id, opts)
  end

  # Private helper to get configured implementation
  defp store_impl do
    Application.get_env(:agent_runtime, :run_store_impl, AgentInfra.StoreEcto.RunStore)
  end
end
