defmodule AgentInfra.StoreEcto.WorkflowStore do
  @moduledoc """
  Ecto implementation of the WorkflowStore behavior.

  This module implements the AgentCore.Stores.WorkflowStore behavior using Ecto
  and PostgreSQL for persistence. It handles conversion between domain structs
  and database schemas.

  Note: This is a placeholder implementation as there are no workflow schemas
  in the current database. This would need to be implemented when workflow
  persistence is added to the system.
  """

  @behaviour AgentCore.Stores.WorkflowStore

  alias AgentCore.{Workflows.Spec, Stores.WorkflowStore}

  # For now, we'll use an in-memory store since there are no workflow schemas
  # This should be replaced with proper Ecto implementation when schemas are added

  @impl WorkflowStore
  def put(%Spec{} = _spec) do
    {:error, :not_implemented}
  end

  @impl WorkflowStore
  def get(_workflow_id, _version \\ nil) do
    {:error, :not_implemented}
  end

  @impl WorkflowStore
  def get_latest(_workflow_id) do
    {:error, :not_implemented}
  end

  @impl WorkflowStore
  def delete(_workflow_id, _version) do
    {:error, :not_implemented}
  end

  @impl WorkflowStore
  def delete_all_versions(_workflow_id) do
    {:error, :not_implemented}
  end

  @impl WorkflowStore
  def list_workflows do
    {:error, :not_implemented}
  end

  @impl WorkflowStore
  def list_versions(_workflow_id) do
    {:error, :not_implemented}
  end

  @impl WorkflowStore
  def list(_opts \\ []) do
    {:error, :not_implemented}
  end

  @impl WorkflowStore
  def count(_opts \\ []) do
    {:error, :not_implemented}
  end

  @impl WorkflowStore
  def exists?(_workflow_id, _version \\ nil) do
    {:error, :not_implemented}
  end

  @impl WorkflowStore
  def next_version(_workflow_id) do
    {:error, :not_implemented}
  end

  @impl WorkflowStore
  def validate_and_put(%Spec{} = _spec) do
    {:error, :not_implemented}
  end
end
