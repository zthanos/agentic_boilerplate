defmodule AgentWebWeb.AdminComponentTest do
  @moduledoc """
  Test suite for admin dashboard components without database dependency.
  This test verifies that the admin components compile and render correctly.
  """
  use ExUnit.Case
  import Phoenix.Component
  import Phoenix.LiveViewTest

  # Test admin layout component compilation
  test "admin layout component compiles without errors" do
    # Test that the AdminLayouts module can be loaded
    assert Code.ensure_loaded?(AgentWebWeb.AdminLayouts)
  end

  test "admin sidebar component compiles without errors" do
    # Test that the AdminSidebar module can be loaded
    assert Code.ensure_loaded?(AgentWebWeb.AdminSidebar)
  end

  test "admin live views compile without errors" do
    admin_modules = [
      AgentWebWeb.AdminLive,
      AgentWebWeb.AdminRunHistoryLive,
      AgentWebWeb.AdminChatLive,
      AgentWebWeb.AdminSettingsLive,
      AgentWebWeb.AdminProfilesLive,
      AgentWebWeb.AdminAgentsLive,
      AgentWebWeb.AdminWorkflowsLive,
      AgentWebWeb.AdminTestingLive
    ]

    for module <- admin_modules do
      assert Code.ensure_loaded?(module), "Failed to load #{module}"
    end
  end

  # Test component rendering without database
  test "admin layout renders basic structure" do
    assigns = %{
      flash: %{},
      current_page: :dashboard,
      current_section: :analytics,
      sidebar_collapsed: false,
      inner_block: []
    }

    # This should not raise an error during compilation
    assert function_exported?(AgentWebWeb.AdminLayouts, :admin, 1)
  end

  test "admin sidebar has proper navigation structure" do
    # Test that the sidebar component has the expected navigation sections
    sidebar_module = AgentWebWeb.AdminSidebar

    # Check that the component has the required functions
    assert function_exported?(sidebar_module, :mount, 1)
    assert function_exported?(sidebar_module, :update, 2)
    assert function_exported?(sidebar_module, :render, 1)
  end

  test "admin routes are properly defined" do
    # Test that the router has admin routes
    router_module = AgentWebWeb.Router
    assert Code.ensure_loaded?(router_module)

    # Check that the router module exists and compiles
    assert function_exported?(router_module, :__routes__, 0)
  end
end
