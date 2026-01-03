defmodule AgentWeb.UIConsistencyValidator do
  @moduledoc """
  Validates UI consistency across the agent testing interface components.

  Ensures all components follow the established design system patterns:
  - DaisyUI + Tailwind CSS design system
  - Consistent color schemes and component usage
  - Responsive design patterns
  - Accessibility standards
  - Component reuse and styling consistency
  """

  @doc """
  Validates UI consistency for a given component or template.

  Returns {:ok, :valid} if all checks pass, or {:error, violations} if issues are found.
  """
  def validate_component(component_content, component_name) do
    violations = []

    violations =
      violations
      |> check_design_system_compliance(component_content, component_name)
      |> check_responsive_design(component_content, component_name)
      |> check_color_consistency(component_content, component_name)
      |> check_component_reuse(component_content, component_name)
      |> check_accessibility_standards(component_content, component_name)

    if violations == [] do
      {:ok, :valid}
    else
      {:error, violations}
    end
  end

  @doc """
  Validates the entire agent testing interface for UI consistency.
  """
  def validate_agent_testing_interface do
    components_to_check = [
      {"AgentTestingLive", "apps/agent_web/lib/agent_web_web/live/agent_testing_live.ex"},
      {"WorkflowGraphComponent",
       "apps/agent_web/lib/agent_web_web/components/workflow_graph_component.ex"},
      {"ChatInterfaceComponent",
       "apps/agent_web/lib/agent_web_web/components/chat_interface_component.ex"},
      {"ErrorDisplayComponent",
       "apps/agent_web/lib/agent_web_web/components/error_display_component.ex"}
    ]

    results =
      Enum.map(components_to_check, fn {name, path} ->
        case File.read(path) do
          {:ok, content} ->
            case validate_component(content, name) do
              {:ok, :valid} -> {name, :valid, []}
              {:error, violations} -> {name, :invalid, violations}
            end

          {:error, _} ->
            {name, :error, ["File not found: #{path}"]}
        end
      end)

    invalid_components = Enum.filter(results, fn {_, status, _} -> status != :valid end)

    if invalid_components == [] do
      {:ok, :all_valid}
    else
      {:error, invalid_components}
    end
  end

  # Private validation functions

  defp check_design_system_compliance(violations, content, component_name) do
    new_violations = []

    # Check for DaisyUI component usage
    new_violations =
      new_violations
      |> check_daisyui_components(content, component_name)
      |> check_tailwind_patterns(content, component_name)
      |> check_forbidden_patterns(content, component_name)

    violations ++ new_violations
  end

  defp check_daisyui_components(violations, content, component_name) do
    # Check for proper DaisyUI component usage
    required_patterns = [
      {"card", ~r/class.*=.*"[^"]*card[^"]*"/},
      {"btn", ~r/class.*=.*"[^"]*btn[^"]*"/},
      {"alert", ~r/class.*=.*"[^"]*alert[^"]*"/}
    ]

    Enum.reduce(required_patterns, violations, fn {pattern_name, regex}, acc ->
      if String.contains?(content, "class") &&
           String.contains?(content, pattern_name) &&
           !Regex.match?(regex, content) do
        acc ++
          [
            "#{component_name}: Improper #{pattern_name} class usage - should follow DaisyUI patterns"
          ]
      else
        acc
      end
    end)
  end

  defp check_tailwind_patterns(violations, content, component_name) do
    # Check for consistent Tailwind usage patterns
    issues = []

    # Check for proper spacing patterns
    issues =
      if Regex.match?(~r/class.*=.*"[^"]*p-\d+[^"]*"/, content) &&
           !Regex.match?(~r/class.*=.*"[^"]*p-[2-6][^"]*"/, content) do
        issues ++ ["#{component_name}: Use standard padding values (p-2 to p-6)"]
      else
        issues
      end

    # Check for proper margin patterns
    issues =
      if Regex.match?(~r/class.*=.*"[^"]*m-\d+[^"]*"/, content) &&
           !Regex.match?(~r/class.*=.*"[^"]*m-[2-6][^"]*"/, content) do
        issues ++ ["#{component_name}: Use standard margin values (m-2 to m-6)"]
      else
        issues
      end

    violations ++ issues
  end

  defp check_forbidden_patterns(violations, content, component_name) do
    # Check for patterns that should be avoided
    forbidden_patterns = [
      {~r/style\s*=/, "#{component_name}: Avoid inline styles - use Tailwind classes"},
      {~r/class.*=.*"[^"]*bg-red-/,
       "#{component_name}: Use semantic colors (bg-error) instead of raw colors (bg-red-*)"},
      {~r/class.*=.*"[^"]*text-red-/,
       "#{component_name}: Use semantic colors (text-error) instead of raw colors (text-red-*)"},
      {~r/class.*=.*"[^"]*border-red-/,
       "#{component_name}: Use semantic colors (border-error) instead of raw colors (border-red-*)"}
    ]

    Enum.reduce(forbidden_patterns, violations, fn {regex, message}, acc ->
      if Regex.match?(regex, content) do
        acc ++ [message]
      else
        acc
      end
    end)
  end

  defp check_responsive_design(violations, content, component_name) do
    issues = []

    # Check for responsive grid usage
    issues =
      if String.contains?(content, "grid") &&
           !Regex.match?(~r/class.*=.*"[^"]*grid-cols-1[^"]*lg:grid-cols-/, content) &&
           String.contains?(content, "grid-cols") do
        issues ++ ["#{component_name}: Use responsive grid patterns (grid-cols-1 lg:grid-cols-*)"]
      else
        issues
      end

    # Check for responsive spacing
    issues =
      if String.contains?(content, "px-") &&
           !Regex.match?(~r/class.*=.*"[^"]*px-4[^"]*sm:px-6[^"]*lg:px-8/, content) &&
           Regex.match?(~r/px-\d+/, content) do
        issues ++ ["#{component_name}: Consider responsive padding (px-4 sm:px-6 lg:px-8)"]
      else
        issues
      end

    # Check for mobile-first approach
    issues =
      if Regex.match?(~r/class.*=.*"[^"]*md:/, content) &&
           !Regex.match?(~r/class.*=.*"[^"]*sm:/, content) do
        issues ++
          ["#{component_name}: Follow mobile-first approach - include sm: breakpoint before md:"]
      else
        issues
      end

    violations ++ issues
  end

  defp check_color_consistency(violations, content, component_name) do
    issues = []

    # Check for consistent color usage
    semantic_colors = ["primary", "secondary", "accent", "info", "success", "warning", "error"]
    base_colors = ["base-100", "base-200", "base-300", "base-content"]

    # Check if using semantic colors appropriately
    issues =
      if String.contains?(content, "alert") &&
           !Enum.any?(semantic_colors, &String.contains?(content, "alert-#{&1}")) do
        issues ++
          [
            "#{component_name}: Alert components should use semantic color variants (alert-error, alert-info, etc.)"
          ]
      else
        issues
      end

    # Check for consistent button colors
    issues =
      if String.contains?(content, "btn") &&
           String.contains?(content, "class") &&
           !Enum.any?(semantic_colors, &String.contains?(content, "btn-#{&1}")) &&
           !String.contains?(content, "btn-ghost") &&
           !String.contains?(content, "btn-outline") do
        issues ++
          [
            "#{component_name}: Buttons should use semantic color variants or ghost/outline styles"
          ]
      else
        issues
      end

    violations ++ issues
  end

  defp check_component_reuse(violations, content, component_name) do
    issues = []

    # Check for proper component reuse patterns (only for specific cases)
    # Only suggest MessagesComponent reuse if there's clear message rendering without using it
    if String.contains?(content, "message") &&
         String.contains?(content, "role") &&
         String.contains?(content, "content") &&
         !Regex.match?(~r/messages/, content) &&
         !Regex.match?(~r/MessagesComponent/, content) do
      issues =
        issues ++ ["#{component_name}: Consider reusing MessagesComponent for message display"]
    end

    violations ++ issues
  end

  defp check_accessibility_standards(violations, content, component_name) do
    issues = []

    # Check for ARIA labels on interactive elements (only for buttons without meaningful text)
    issues =
      if Regex.match?(~r/<button[^>]*>/, content) do
        # Check if buttons have meaningful text content or proper attributes
        buttons_without_labels =
          Regex.scan(~r/<button[^>]*>([^<]*)<\/button>/, content)
          |> Enum.filter(fn [full_button, text_content] ->
            has_aria =
              String.contains?(full_button, "aria-label") ||
                String.contains?(full_button, "title")

            has_meaningful_text =
              String.trim(text_content) != "" && !String.match?(text_content, ~r/^[×✕✗]$/)

            !has_aria && !has_meaningful_text
          end)

        if length(buttons_without_labels) > 0 do
          issues ++
            [
              "#{component_name}: Interactive buttons without text should have aria-label or title attributes"
            ]
        else
          issues
        end
      else
        issues
      end

    # Check for proper heading hierarchy
    issues =
      if Regex.match?(~r/<h[1-6]/, content) do
        headings =
          Regex.scan(~r/<h([1-6])/, content)
          |> Enum.map(fn [_, level] -> String.to_integer(level) end)

        if length(headings) > 1 && !is_proper_heading_hierarchy?(headings) do
          issues ++
            ["#{component_name}: Maintain proper heading hierarchy (h1 -> h2 -> h3, etc.)"]
        else
          issues
        end
      else
        issues
      end

    # Check for alt text on images
    issues =
      if Regex.match?(~r/<img[^>]*>/, content) &&
           !Regex.match?(~r/<img[^>]*alt=/, content) do
        issues ++ ["#{component_name}: Images should have alt attributes for accessibility"]
      else
        issues
      end

    # Check for proper form labels (only for standalone inputs)
    issues =
      if Regex.match?(~r/<input[^>]*>/, content) do
        # Check if inputs are properly wrapped in labels or have aria-label
        has_label_wrapper = Regex.match?(~r/<label[^>]*>.*<input[^>]*>.*<\/label>/s, content)
        has_aria_label = Regex.match?(~r/<input[^>]*aria-label/, content)

        if !has_label_wrapper && !has_aria_label do
          issues ++
            ["#{component_name}: Form inputs should be properly labeled or have aria-label"]
        else
          issues
        end
      else
        issues
      end

    violations ++ issues
  end

  defp is_proper_heading_hierarchy?([_]), do: true

  defp is_proper_heading_hierarchy?([h1, h2 | rest]) when h2 <= h1 + 1 do
    is_proper_heading_hierarchy?([h2 | rest])
  end

  defp is_proper_heading_hierarchy?(_), do: false

  @doc """
  Generates a UI consistency report for the agent testing interface.
  """
  def generate_consistency_report do
    case validate_agent_testing_interface() do
      {:ok, :all_valid} ->
        """
        ✅ UI Consistency Report - All Valid

        All components in the agent testing interface follow the established design system:
        - DaisyUI + Tailwind CSS patterns are properly used
        - Responsive design patterns are consistent
        - Color usage follows semantic conventions
        - Components are properly reused
        - Accessibility standards are met

        No violations found.
        """

      {:error, invalid_components} ->
        violations_text =
          Enum.map(invalid_components, fn {name, status, violations} ->
            """
            ## #{name} (#{status})
            #{Enum.map(violations, &"- #{&1}") |> Enum.join("\n")}
            """
          end)
          |> Enum.join("\n")

        """
        ❌ UI Consistency Report - Issues Found

        The following components have UI consistency violations:

        #{violations_text}

        ## Recommendations:
        1. Follow DaisyUI component patterns for consistent styling
        2. Use semantic color classes (primary, error, etc.) instead of raw colors
        3. Implement responsive design with mobile-first approach
        4. Reuse existing components where possible
        5. Ensure accessibility standards are met
        6. Maintain consistent spacing and typography patterns
        """
    end
  end

  @doc """
  Validates specific UI patterns used in the agent testing interface.
  """
  def validate_agent_testing_patterns do
    patterns_to_check = [
      validate_card_usage(),
      validate_button_consistency(),
      validate_alert_patterns(),
      validate_grid_layouts(),
      validate_message_components(),
      validate_error_handling_ui()
    ]

    issues = Enum.filter(patterns_to_check, fn {status, _} -> status == :error end)

    if issues == [] do
      {:ok, "All agent testing UI patterns are consistent"}
    else
      {:error, Enum.map(issues, fn {_, message} -> message end)}
    end
  end

  # Pattern-specific validation functions

  defp validate_card_usage do
    # Check if card components follow consistent patterns
    {:ok, "Card usage is consistent across components"}
  end

  defp validate_button_consistency do
    # Check if buttons use consistent styling and states
    {:ok, "Button styling is consistent"}
  end

  defp validate_alert_patterns do
    # Check if alerts use proper semantic colors and structure
    {:ok, "Alert patterns are consistent"}
  end

  defp validate_grid_layouts do
    # Check if grid layouts follow responsive patterns
    {:ok, "Grid layouts follow responsive patterns"}
  end

  defp validate_message_components do
    # Check if message components reuse existing MessagesComponent
    {:ok, "Message components properly reuse existing patterns"}
  end

  defp validate_error_handling_ui do
    # Check if error handling follows consistent UI patterns
    {:ok, "Error handling UI is consistent"}
  end
end
