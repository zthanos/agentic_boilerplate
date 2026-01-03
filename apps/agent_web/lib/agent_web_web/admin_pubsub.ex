defmodule AgentWebWeb.AdminPubSub do
  @moduledoc """
  PubSub helper for broadcasting admin-related events and metrics updates.
  """

  @doc """
  Broadcasts system metrics updates to all connected admin dashboards.
  """
  def broadcast_metrics_update(metrics) do
    Phoenix.PubSub.broadcast(
      AgentWeb.PubSub,
      "admin:metrics",
      {:metrics_updated, metrics}
    )
  end

  @doc """
  Broadcasts run creation event to admin interfaces.
  """
  def broadcast_run_created(run) do
    Phoenix.PubSub.broadcast(
      AgentWeb.PubSub,
      "admin:runs",
      {:run_created, run}
    )
  end

  @doc """
  Broadcasts run update event to admin interfaces.
  """
  def broadcast_run_updated(run) do
    Phoenix.PubSub.broadcast(
      AgentWeb.PubSub,
      "admin:runs",
      {:run_updated, run}
    )
  end

  @doc """
  Broadcasts run completion event to admin interfaces.
  """
  def broadcast_run_completed(run) do
    Phoenix.PubSub.broadcast(
      AgentWeb.PubSub,
      "admin:runs",
      {:run_completed, run}
    )
  end

  @doc """
  Broadcasts system health status changes.
  """
  def broadcast_health_status_change(status) do
    Phoenix.PubSub.broadcast(
      AgentWeb.PubSub,
      "admin:health",
      {:health_status_changed, status}
    )
  end

  @doc """
  Broadcasts user activity events for the activity feed.
  """
  def broadcast_user_activity(activity) do
    Phoenix.PubSub.broadcast(
      AgentWeb.PubSub,
      "admin:activity",
      {:new_activity, activity}
    )
  end
end
