defmodule AgentWebWeb.AdminErrorHandler do
  @moduledoc """
  Error handling utilities for admin dashboard LiveViews.

  Provides consistent error handling patterns, graceful degradation,
  and user feedback mechanisms across all admin components.

  This module provides macros that expand to proper LiveView code
  in the calling context where assign/3 and put_flash/3 are available.
  """

  defmacro handle_mount_error(socket, mount_fn) do
    quote do
      try do
        result = unquote(mount_fn).(unquote(socket))
        {:ok, result}
      rescue
        error ->
          error_message = AgentWebWeb.AdminErrorHandler.format_error_message(error)

          socket =
            unquote(socket)
            |> assign(:loading, false)
            |> assign(:mount_error, error_message)
            |> put_flash(:error, "Failed to load page: #{error_message}")

          {:ok, socket}
      end
    end
  end

  defmacro handle_event_error(socket, event_fn) do
    quote do
      try do
        unquote(event_fn).(unquote(socket))
      rescue
        error ->
          error_message = AgentWebWeb.AdminErrorHandler.format_error_message(error)

          {:noreply,
           unquote(socket)
           |> assign(:loading, false)
           |> put_flash(:error, "Operation failed: #{error_message}")}
      end
    end
  end

  defmacro handle_data_loading(socket, assign_key, load_fn) do
    quote do
      socket = assign(unquote(socket), :"#{unquote(assign_key)}_loading", true)

      try do
        data = unquote(load_fn).()

        socket
        |> assign(unquote(assign_key), data)
        |> assign(:"#{unquote(assign_key)}_loading", false)
        |> assign(:"#{unquote(assign_key)}_error", nil)
      rescue
        error ->
          error_message = AgentWebWeb.AdminErrorHandler.format_error_message(error)

          socket
          |> assign(:"#{unquote(assign_key)}_loading", false)
          |> assign(:"#{unquote(assign_key)}_error", error_message)
          |> assign(
            unquote(assign_key),
            AgentWebWeb.AdminErrorHandler.get_fallback_data(unquote(assign_key))
          )
      end
    end
  end

  @doc """
  Formats error messages for user display.
  """
  def format_error_message(error) do
    case error do
      %Ecto.Query.CastError{} ->
        "Invalid data format"

      %Ecto.NoResultsError{} ->
        "Requested data not found"

      %DBConnection.ConnectionError{} ->
        "Database connection failed"

      %Jason.DecodeError{} ->
        "Invalid response format"

      %{reason: :timeout} ->
        "Request timed out"

      %{reason: :econnrefused} ->
        "Service unavailable"

      %ArgumentError{message: message} ->
        "Invalid input: #{message}"

      %RuntimeError{message: message} ->
        message

      error when is_binary(error) ->
        error

      error when is_atom(error) ->
        error |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()

      _error ->
        "An unexpected error occurred"
    end
  end

  @doc """
  Gets fallback data for different assign keys when services fail.
  """
  def get_fallback_data(assign_key) do
    case assign_key do
      :system_metrics ->
        %{
          total_runs: 0,
          active_sessions: 0,
          health_status: "Unknown",
          avg_response_time: "N/A",
          services: [],
          recent_activities: []
        }

      :run_history ->
        []

      :agents ->
        []

      :workflows ->
        []

      :settings ->
        %{}

      :profiles ->
        []

      :chat_sessions ->
        []

      _other ->
        nil
    end
  end

  @doc """
  Checks service health and returns status information.
  """
  def check_service_health(service_name) do
    case service_name do
      :database ->
        try do
          # Simple database health check
          Ecto.Adapters.SQL.query!(AgentCore.Repo, "SELECT 1", [])
          {:healthy, "Connection: #{get_db_latency()}ms"}
        rescue
          _error ->
            {:error, "Database connection failed"}
        end

      :pubsub ->
        try do
          Phoenix.PubSub.node_name(AgentWeb.PubSub)
          {:healthy, "PubSub operational"}
        rescue
          _error ->
            {:error, "PubSub service unavailable"}
        end

      :external_api ->
        # Mock external API health check
        case :rand.uniform(10) do
          n when n <= 8 -> {:healthy, "API responding normally"}
          9 -> {:degraded, "API experiencing delays"}
          10 -> {:error, "API service unavailable"}
        end

      _unknown ->
        {:error, "Unknown service"}
    end
  end

  # Gets database connection latency for health reporting.
  defp get_db_latency do
    start_time = System.monotonic_time(:millisecond)

    try do
      Ecto.Adapters.SQL.query!(AgentCore.Repo, "SELECT 1", [])
      System.monotonic_time(:millisecond) - start_time
    rescue
      _error ->
        999
    end
  end

  @doc """
  Creates a standardized error response for API endpoints.
  """
  def api_error_response(error, status \\ 500) do
    %{
      error: true,
      message: format_error_message(error),
      status: status,
      timestamp: DateTime.utc_now()
    }
  end

  @doc """
  Logs errors with appropriate context for debugging.
  """
  def log_error(error, context \\ %{}) do
    require Logger

    error_details = %{
      error: inspect(error),
      context: context,
      timestamp: DateTime.utc_now(),
      stacktrace: Process.info(self(), :current_stacktrace)
    }

    Logger.error("Admin dashboard error: #{inspect(error_details)}")
  end
end
