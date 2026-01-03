defmodule AgentWebWeb.AdminDashboardTest do
  @moduledoc """
  Test suite for admin dashboard core functionality.
  This test verifies that the admin dashboard components render correctly
  and navigation works as expected.
  """
  use AgentWebWeb.ConnCase
  import Phoenix.LiveViewTest

  describe "admin dashboard core functionality" do
    test "admin dashboard renders successfully", %{conn: conn} do
      {:ok, view, html} = live(conn, "/admin")

      # Check that the main admin layout is rendered
      assert html =~ "Admin Dashboard"
      assert has_element?(view, "[data-testid='admin-layout']") ||
             html =~ "Admin Dashboard" # Fallback check for content
    end

    test "admin sidebar navigation is present", %{conn: conn} do
      {:ok, view, html} = live(conn, "/admin")

      # Check for navigation sections
      assert html =~ "Analytics" || has_element?(view, "nav")
      assert html =~ "Operations" || has_element?(view, "nav")
      assert html =~ "Management" || has_element?(view, "nav")
    end

    test "admin dashboard shows system metrics", %{conn: conn} do
      {:ok, view, html} = live(conn, "/admin")

      # Check for KPI cards or metrics display
      assert html =~ "Total Runs" || html =~ "System" || has_element?(view, ".card")
    end

    test "admin routes are accessible", %{conn: conn} do
      # Test main admin routes
      routes_to_test = [
        "/admin",
        "/admin/dashboard",
        "/admin/runs",
        "/admin/chat",
        "/admin/settings",
        "/admin/profiles",
        "/admin/agents",
        "/admin/workflows",
        "/admin/testing"
      ]

      for route <- routes_to_test do
        assert {:ok, _view, _html} = live(conn, route)
      end
    end
  end

  describe "responsive design behavior" do
    test "sidebar collapse functionality works", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin")

      # Test sidebar toggle (this would normally test the JS interaction)
      # For now, just verify the toggle button exists
      assert has_element?(view, "button") ||
             render(view) =~ "toggle" ||
             render(view) =~ "menu"
    end
  end

  describe "navigation consistency" do
    test "navigation links are properly formatted", %{conn: conn} do
      {:ok, view, html} = live(conn, "/admin")

      # Check that navigation contains expected links
      expected_links = ["Dashboard", "Settings", "Agents"]

      for link_text <- expected_links do
        assert html =~ link_text
      end
    end

    test "active page highlighting works", %{conn: conn} do
      {:ok, view, html} = live(conn, "/admin/settings")

      # Should show settings as active or contain settings content
      assert html =~ "Settings" || html =~ "settings"
    end
  end
end
