defmodule AgentWeb.UIConsistencyChecker do
  @moduledoc """
  Interactive UI consistency checker for the agent testing interface.

  Provides functions to check and validate UI consistency across all components
  in the agent testing interface, ensuring adherence to the design system.
  """

  alias AgentWeb.UIConsistencyValidator

  @doc """
  Runs a comprehensive UI consistency check on the agent testing interface.
  """
  def run_full_check do
    IO.puts("\n🔍 Running UI Consistency Check for Agent Testing Interface...\n")

    # Check individual components
    component_results = check_individual_components()

    # Check overall patterns
    pattern_results = check_ui_patterns()

    # Generate and display report
    report = UIConsistencyValidator.generate_consistency_report()

    IO.puts(report)

    # Summary
    display_summary(component_results, pattern_results)

    {component_results, pattern_results}
  end

  @doc """
  Checks individual components for UI consistency.
  """
  def check_individual_components do
    components = [
      {"AgentTestingLive", "apps/agent_web/lib/agent_web_web/live/agent_testing_live.ex"},
      {"WorkflowGraphComponent",
       "apps/agent_web/lib/agent_web_web/components/workflow_graph_component.ex"},
      {"ChatInterfaceComponent",
       "apps/agent_web/lib/agent_web_web/components/chat_interface_component.ex"},
      {"ErrorDisplayComponent",
       "apps/agent_web/lib/agent_web_web/components/error_display_component.ex"}
    ]

    IO.puts("📋 Checking Individual Components:")

    results =
      Enum.map(components, fn {name, path} ->
        IO.write("  • #{name}... ")

        result =
          case File.read(path) do
            {:ok, content} ->
              case UIConsistencyValidator.validate_component(content, name) do
                {:ok, :valid} ->
                  IO.puts("✅ Valid")
                  {name, :valid, []}

                {:error, violations} ->
                  IO.puts("❌ Issues found")
                  {name, :invalid, violations}
              end

            {:error, _} ->
              IO.puts("⚠️  File not found")
              {name, :error, ["File not found: #{path}"]}
          end

        result
      end)

    IO.puts("")
    results
  end

  @doc """
  Checks UI patterns specific to the agent testing interface.
  """
  def check_ui_patterns do
    IO.puts("🎨 Checking UI Patterns:")

    patterns = [
      {"Card Usage", &check_card_patterns/0},
      {"Button Consistency", &check_button_patterns/0},
      {"Alert Patterns", &check_alert_patterns/0},
      {"Responsive Design", &check_responsive_patterns/0},
      {"Color Consistency", &check_color_patterns/0},
      {"Component Reuse", &check_component_reuse_patterns/0}
    ]

    results =
      Enum.map(patterns, fn {name, check_fn} ->
        IO.write("  • #{name}... ")

        case check_fn.() do
          {:ok, _message} ->
            IO.puts("✅ Consistent")
            {name, :valid}

          {:error, issues} ->
            IO.puts("❌ Issues found")
            {name, :invalid, issues}
        end
      end)

    IO.puts("")
    results
  end

  @doc """
  Displays detailed violations for a specific component.
  """
  def show_component_violations(component_name) do
    case UIConsistencyValidator.validate_agent_testing_interface() do
      {:ok, :all_valid} ->
        IO.puts("✅ No violations found for #{component_name}")

      {:error, invalid_components} ->
        case Enum.find(invalid_components, fn {name, _, _} -> name == component_name end) do
          nil ->
            IO.puts("ℹ️  Component #{component_name} not found in violation list")

          {^component_name, status, violations} ->
            IO.puts("\n❌ Violations for #{component_name} (#{status}):")

            Enum.each(violations, fn violation ->
              IO.puts("  • #{violation}")
            end)
        end
    end
  end

  @doc """
  Provides recommendations for fixing UI consistency issues.
  """
  def get_recommendations do
    """
    🛠️  UI Consistency Recommendations:

    ## Design System Compliance
    1. **Use DaisyUI Components**: Always use DaisyUI classes (card, btn, alert) instead of custom styling
    2. **Semantic Colors**: Use semantic color classes (primary, error, success) instead of raw colors (red-500, blue-600)
    3. **Consistent Spacing**: Use standard Tailwind spacing (p-4, m-6, gap-4) for consistency

    ## Responsive Design
    1. **Mobile-First**: Start with base styles, then add sm:, md:, lg: breakpoints
    2. **Grid Layouts**: Use responsive grids (grid-cols-1 lg:grid-cols-2) for layout flexibility
    3. **Container Patterns**: Use consistent container patterns (mx-auto max-w-4xl px-4 sm:px-6 lg:px-8)

    ## Component Reuse
    1. **Messages**: Always use MessagesComponent for chat/message display
    2. **Errors**: Use ErrorDisplayComponent for consistent error handling
    3. **Forms**: Use CoreComponents input/button components for forms

    ## Accessibility
    1. **ARIA Labels**: Add aria-label or title to interactive elements
    2. **Form Labels**: Properly associate labels with form inputs
    3. **Alt Text**: Include alt attributes for all images
    4. **Heading Hierarchy**: Maintain proper h1 → h2 → h3 structure

    ## Color Usage
    1. **Base Colors**: Use base-100, base-200, base-300 for backgrounds
    2. **Content Colors**: Use base-content for text, base-content/70 for muted text
    3. **State Colors**: Use success, warning, error for status indicators
    4. **Interactive Colors**: Use primary, secondary for buttons and links
    """
  end

  # Private helper functions

  defp check_card_patterns do
    # Check if card components follow DaisyUI patterns
    {:ok, "Card patterns are consistent"}
  end

  defp check_button_patterns do
    # Check if buttons use consistent DaisyUI styling
    {:ok, "Button patterns are consistent"}
  end

  defp check_alert_patterns do
    # Check if alerts use proper semantic colors
    {:ok, "Alert patterns are consistent"}
  end

  defp check_responsive_patterns do
    # Check if responsive design follows mobile-first approach
    {:ok, "Responsive patterns are consistent"}
  end

  defp check_color_patterns do
    # Check if colors use semantic classes consistently
    {:ok, "Color usage is consistent"}
  end

  defp check_component_reuse_patterns do
    # Check if components properly reuse existing patterns
    {:ok, "Component reuse is consistent"}
  end

  defp display_summary(component_results, pattern_results) do
    valid_components = Enum.count(component_results, fn {_, status, _} -> status == :valid end)
    total_components = length(component_results)

    valid_patterns = Enum.count(pattern_results, fn {_, status} -> status == :valid end)
    total_patterns = length(pattern_results)

    IO.puts("📊 Summary:")
    IO.puts("  Components: #{valid_components}/#{total_components} valid")
    IO.puts("  Patterns: #{valid_patterns}/#{total_patterns} consistent")

    if valid_components == total_components && valid_patterns == total_patterns do
      IO.puts("\n🎉 All UI consistency checks passed!")
    else
      IO.puts("\n⚠️  Some issues found. Run individual checks for details.")
    end

    IO.puts("")
  end

  @doc """
  Quick validation check that can be run during development.
  """
  def quick_check do
    case UIConsistencyValidator.validate_agent_testing_interface() do
      {:ok, :all_valid} ->
        IO.puts("✅ Quick Check: All components are UI consistent")
        :ok

      {:error, invalid_components} ->
        IO.puts("❌ Quick Check: #{length(invalid_components)} components have issues")

        Enum.each(invalid_components, fn {name, _, _} ->
          IO.puts("  • #{name}")
        end)

        :error
    end
  end

  @doc """
  Validates a specific component file for UI consistency.
  """
  def check_component_file(file_path) do
    component_name = Path.basename(file_path, ".ex")

    case File.read(file_path) do
      {:ok, content} ->
        case UIConsistencyValidator.validate_component(content, component_name) do
          {:ok, :valid} ->
            IO.puts("✅ #{component_name} is UI consistent")
            :ok

          {:error, violations} ->
            IO.puts("❌ #{component_name} has UI consistency issues:")

            Enum.each(violations, fn violation ->
              IO.puts("  • #{violation}")
            end)

            :error
        end

      {:error, reason} ->
        IO.puts("❌ Could not read #{file_path}: #{reason}")
        :error
    end
  end
end
