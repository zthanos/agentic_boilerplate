defmodule AgentCore.TestAssessment.PhoenixAnalysis do
  @moduledoc """
  Module responsible for Phoenix-specific test analysis features.

  Provides specialized analysis for:
  - LiveView interaction pattern analysis
  - Form validation test coverage detection
  - Phoenix component untested interaction identification
  - Property-based test opportunity detection for parsers and transformations
  """

  require Logger

  alias AgentCore.TestAssessment.{ParsedTest, CoverageGap, Recommendation}

  # LiveView interaction patterns to detect
  @liveview_interaction_patterns [
    # Event handling patterns
    ~r/handle_event\s*\(\s*"[^"]+"/,
    ~r/phx-click\s*=\s*"[^"]+"/,
    ~r/phx-submit\s*=\s*"[^"]+"/,
    ~r/phx-change\s*=\s*"[^"]+"/,
    ~r/phx-blur\s*=\s*"[^"]+"/,
    ~r/phx-focus\s*=\s*"[^"]+"/,
    ~r/phx-keydown\s*=\s*"[^"]+"/,
    ~r/phx-keyup\s*=\s*"[^"]+"/,

    # LiveView test patterns
    ~r/render_click\s*\(/,
    ~r/render_submit\s*\(/,
    ~r/render_change\s*\(/,
    ~r/render_blur\s*\(/,
    ~r/render_focus\s*\(/,
    ~r/render_keydown\s*\(/,
    ~r/render_keyup\s*\(/,

    # Element interaction patterns
    ~r/element\s*\(\s*[^,]+,\s*"[^"]+"\s*\)/,
    ~r/has_element\?\s*\(/,
    ~r/refute_element\s*\(/
  ]

  # Form validation patterns
  @form_validation_patterns [
    # Changeset validation patterns
    ~r/validate_required\s*\(/,
    ~r/validate_length\s*\(/,
    ~r/validate_format\s*\(/,
    ~r/validate_number\s*\(/,
    ~r/validate_inclusion\s*\(/,
    ~r/validate_exclusion\s*\(/,
    ~r/validate_confirmation\s*\(/,
    ~r/validate_acceptance\s*\(/,
    ~r/validate_subset\s*\(/,
    ~r/validate_change\s*\(/,

    # Form test patterns
    ~r/form\s*\(\s*@[^,]+/,
    ~r/input\s*field\s*=\s*{@[^}]+}/,
    ~r/phx-change\s*=\s*"validate"/,
    ~r/phx-submit\s*=\s*"save"/,

    # Error handling patterns
    ~r/errors\s*on\s*\(/,
    ~r/changeset\.errors/,
    ~r/form\.errors/
  ]

  # Phoenix component patterns
  @component_patterns [
    # Component definition patterns
    ~r/defmodule\s+[^.]+\.Components?\./,
    ~r/use\s+Phoenix\.Component/,
    ~r/use\s+Phoenix\.LiveComponent/,
    ~r/def\s+[a-z_]+\s*\(\s*assigns\s*\)/,
    ~r/attr\s+:[a-z_]+/,
    ~r/slot\s+:[a-z_]+/,

    # Component usage patterns
    ~r/<\.[a-z_]+[^>]*>/,
    ~r/<:[a-z_]+[^>]*>/,
    ~r/render_component\s*\(/,

    # Component test patterns
    ~r/render_component\s*\([^,]+,\s*%{[^}]*}/,
    ~r/has_element\?\s*\([^,]+,\s*"[^"]*\.[a-z_]+"/
  ]

  # Parser and transformation patterns for property-based testing
  @parser_transformation_patterns [
    # Parser patterns
    ~r/def\s+parse[_a-z]*\s*\(/,
    ~r/def\s+decode[_a-z]*\s*\(/,
    ~r/def\s+from_[a-z_]+\s*\(/,
    ~r/Jason\.decode/,
    ~r/Poison\.decode/,
    ~r/XML\.parse/,
    ~r/CSV\.parse/,

    # Transformation patterns
    ~r/def\s+transform[_a-z]*\s*\(/,
    ~r/def\s+convert[_a-z]*\s*\(/,
    ~r/def\s+to_[a-z_]+\s*\(/,
    ~r/Enum\.map\s*\(/,
    ~r/Enum\.reduce\s*\(/,
    ~r/Stream\.map\s*\(/,

    # Serialization patterns
    ~r/def\s+encode[_a-z]*\s*\(/,
    ~r/Jason\.encode/,
    ~r/Poison\.encode/,
    ~r/XML\.generate/
  ]

  @doc """
  Analyzes LiveView interaction patterns in the test suite.

  Identifies tested and untested LiveView interactions, including event handlers,
  UI interactions, and component interactions.
  """
  @spec analyze_liveview_interactions([ParsedTest.t()]) :: %{
    tested_interactions: [String.t()],
    untested_interactions: [String.t()],
    interaction_coverage: float(),
    recommendations: [Recommendation.t()]
  }
  def analyze_liveview_interactions(parsed_tests) do
    Logger.info("Analyzing LiveView interaction patterns...")

    # Find all LiveView tests
    liveview_tests = Enum.filter(parsed_tests, &is_liveview_test?/1)

    # Extract tested interactions
    tested_interactions = extract_tested_interactions(liveview_tests)

    # Identify potential untested interactions from source patterns
    all_potential_interactions = extract_potential_interactions(parsed_tests)
    untested_interactions = all_potential_interactions -- tested_interactions

    # Calculate coverage
    total_interactions = length(all_potential_interactions)
    tested_count = length(tested_interactions)
    coverage = if total_interactions > 0, do: tested_count / total_interactions * 100, else: 100.0

    # Generate recommendations
    recommendations = generate_liveview_recommendations(untested_interactions, coverage)

    %{
      tested_interactions: tested_interactions,
      untested_interactions: untested_interactions,
      interaction_coverage: coverage,
      recommendations: recommendations
    }
  end

  @doc """
  Detects form validation test coverage.

  Analyzes which form validations are tested and identifies gaps in
  validation testing coverage.
  """
  @spec detect_form_validation_coverage([ParsedTest.t()]) :: %{
    tested_validations: [String.t()],
    untested_validations: [String.t()],
    validation_coverage: float(),
    coverage_gaps: [CoverageGap.t()]
  }
  def detect_form_validation_coverage(parsed_tests) do
    Logger.info("Detecting form validation test coverage...")

    # Find tests that include form validation patterns
    validation_tests = Enum.filter(parsed_tests, &has_validation_patterns?/1)

    # Extract tested validations
    tested_validations = extract_tested_validations(validation_tests)

    # Identify potential validations from all tests (including source references)
    all_potential_validations = extract_potential_validations(parsed_tests)
    untested_validations = all_potential_validations -- tested_validations

    # Calculate coverage
    total_validations = length(all_potential_validations)
    tested_count = length(tested_validations)
    coverage = if total_validations > 0, do: tested_count / total_validations * 100, else: 100.0

    # Generate coverage gaps
    coverage_gaps = generate_validation_coverage_gaps(untested_validations)

    %{
      tested_validations: tested_validations,
      untested_validations: untested_validations,
      validation_coverage: coverage,
      coverage_gaps: coverage_gaps
    }
  end

  @doc """
  Identifies untested Phoenix component interactions.

  Analyzes component definitions and usage to identify components that
  lack proper interaction testing.
  """
  @spec identify_untested_component_interactions([ParsedTest.t()]) :: %{
    tested_components: [String.t()],
    untested_components: [String.t()],
    component_coverage: float(),
    coverage_gaps: [CoverageGap.t()]
  }
  def identify_untested_component_interactions(parsed_tests) do
    Logger.info("Identifying untested Phoenix component interactions...")

    # Find component-related tests
    component_tests = Enum.filter(parsed_tests, &has_component_patterns?/1)

    # Extract tested components
    tested_components = extract_tested_components(component_tests)

    # Identify all potential components from source patterns
    all_potential_components = extract_potential_components(parsed_tests)
    untested_components = all_potential_components -- tested_components

    # Calculate coverage
    total_components = length(all_potential_components)
    tested_count = length(tested_components)
    coverage = if total_components > 0, do: tested_count / total_components * 100, else: 100.0

    # Generate coverage gaps
    coverage_gaps = generate_component_coverage_gaps(untested_components)

    %{
      tested_components: tested_components,
      untested_components: untested_components,
      component_coverage: coverage,
      coverage_gaps: coverage_gaps
    }
  end

  @doc """
  Detects opportunities for property-based testing in parsers and transformations.

  Identifies functions that would benefit from property-based testing,
  particularly parsers, serializers, and data transformations.
  """
  @spec detect_property_test_opportunities([ParsedTest.t()]) :: %{
    parser_opportunities: [String.t()],
    transformation_opportunities: [String.t()],
    existing_property_tests: [String.t()],
    recommendations: [Recommendation.t()]
  }
  def detect_property_test_opportunities(parsed_tests) do
    Logger.info("Detecting property-based test opportunities...")

    # Find existing property-based tests
    existing_property_tests = extract_existing_property_tests(parsed_tests)

    # Identify parser opportunities
    parser_opportunities = extract_parser_opportunities(parsed_tests)

    # Identify transformation opportunities
    transformation_opportunities = extract_transformation_opportunities(parsed_tests)

    # Filter out already tested functions
    tested_functions = extract_tested_function_names(existing_property_tests)
    untested_parsers = parser_opportunities -- tested_functions
    untested_transformations = transformation_opportunities -- tested_functions

    # Generate recommendations
    recommendations = generate_property_test_recommendations(
      untested_parsers,
      untested_transformations
    )

    %{
      parser_opportunities: untested_parsers,
      transformation_opportunities: untested_transformations,
      existing_property_tests: existing_property_tests,
      recommendations: recommendations
    }
  end

  @doc """
  Performs comprehensive Phoenix-specific analysis.

  Combines all Phoenix-specific analysis features into a single report.
  """
  @spec analyze_phoenix_features([ParsedTest.t()]) :: %{
    liveview_analysis: map(),
    form_validation_analysis: map(),
    component_analysis: map(),
    property_test_analysis: map(),
    overall_phoenix_coverage: float(),
    phoenix_recommendations: [Recommendation.t()]
  }
  def analyze_phoenix_features(parsed_tests) do
    Logger.info("Performing comprehensive Phoenix-specific analysis...")

    # Run all Phoenix-specific analyses
    liveview_analysis = analyze_liveview_interactions(parsed_tests)
    form_validation_analysis = detect_form_validation_coverage(parsed_tests)
    component_analysis = identify_untested_component_interactions(parsed_tests)
    property_test_analysis = detect_property_test_opportunities(parsed_tests)

    # Calculate overall Phoenix coverage
    overall_coverage = calculate_overall_phoenix_coverage([
      liveview_analysis.interaction_coverage,
      form_validation_analysis.validation_coverage,
      component_analysis.component_coverage
    ])

    # Combine all recommendations
    all_recommendations =
      liveview_analysis.recommendations ++
      property_test_analysis.recommendations

    %{
      liveview_analysis: liveview_analysis,
      form_validation_analysis: form_validation_analysis,
      component_analysis: component_analysis,
      property_test_analysis: property_test_analysis,
      overall_phoenix_coverage: overall_coverage,
      phoenix_recommendations: all_recommendations
    }
  end

  # Private helper functions

  defp is_liveview_test?(test) do
    test_content = build_test_content(test)

    liveview_indicators = [
      "LiveViewTest",
      "render_click",
      "render_submit",
      "render_change",
      "has_element",
      "element",
      "live_view",
      "mount"
    ]

    Enum.any?(liveview_indicators, &String.contains?(test_content, &1))
  end

  defp has_validation_patterns?(test) do
    test_content = build_test_content(test)
    Enum.any?(@form_validation_patterns, &Regex.match?(&1, test_content))
  end

  defp has_component_patterns?(test) do
    test_content = build_test_content(test)
    Enum.any?(@component_patterns, &Regex.match?(&1, test_content))
  end

  defp build_test_content(test) do
    [
      test.name,
      test.file_path,
      Enum.join(test.setup_blocks, " "),
      Enum.join(test.assertions, " "),
      Enum.join(test.dependencies, " ")
    ]
    |> Enum.join(" ")
  end

  defp extract_tested_interactions(liveview_tests) do
    liveview_tests
    |> Enum.flat_map(fn test ->
      test_content = build_test_content(test)

      @liveview_interaction_patterns
      |> Enum.flat_map(fn pattern ->
        Regex.scan(pattern, test_content, capture: :all_but_first)
        |> List.flatten()
      end)
    end)
    |> Enum.uniq()
  end

  defp extract_potential_interactions(parsed_tests) do
    # This would ideally scan source files, but for now we'll extract from test references
    parsed_tests
    |> Enum.flat_map(fn test ->
      test_content = build_test_content(test)

      # Look for handle_event definitions and phx- attributes in test content
      event_handlers = Regex.scan(~r/handle_event\s*\(\s*"([^"]+)"/, test_content, capture: :all_but_first)
                      |> List.flatten()

      phx_events = Regex.scan(~r/phx-[a-z]+\s*=\s*"([^"]+)"/, test_content, capture: :all_but_first)
                   |> List.flatten()

      event_handlers ++ phx_events
    end)
    |> Enum.uniq()
  end

  defp extract_tested_validations(validation_tests) do
    validation_tests
    |> Enum.flat_map(fn test ->
      test_content = build_test_content(test)

      @form_validation_patterns
      |> Enum.flat_map(fn pattern ->
        case Regex.scan(pattern, test_content) do
          [] -> []
          matches -> [extract_validation_name(pattern, hd(matches))]
        end
      end)
    end)
    |> Enum.filter(& &1 != nil)
    |> Enum.uniq()
  end

  defp extract_potential_validations(parsed_tests) do
    parsed_tests
    |> Enum.flat_map(fn test ->
      test_content = build_test_content(test)

      # Look for validation function calls
      Regex.scan(~r/validate_([a-z_]+)\s*\(/, test_content, capture: :all_but_first)
      |> List.flatten()
      |> Enum.map(&("validate_" <> &1))
    end)
    |> Enum.uniq()
  end

  defp extract_tested_components(component_tests) do
    component_tests
    |> Enum.flat_map(fn test ->
      test_content = build_test_content(test)

      # Extract component names from test content
      component_calls = Regex.scan(~r/<\.([a-z_]+)[^>]*>/, test_content, capture: :all_but_first)
                       |> List.flatten()

      slot_calls = Regex.scan(~r/<:([a-z_]+)[^>]*>/, test_content, capture: :all_but_first)
                   |> List.flatten()

      component_calls ++ slot_calls
    end)
    |> Enum.uniq()
  end

  defp extract_potential_components(parsed_tests) do
    parsed_tests
    |> Enum.flat_map(fn test ->
      test_content = build_test_content(test)

      # Look for component definitions and usage patterns
      component_defs = Regex.scan(~r/def\s+([a-z_]+)\s*\(\s*assigns\s*\)/, test_content, capture: :all_but_first)
                      |> List.flatten()

      component_usage = Regex.scan(~r/<\.([a-z_]+)/, test_content, capture: :all_but_first)
                       |> List.flatten()

      component_defs ++ component_usage
    end)
    |> Enum.uniq()
  end

  defp extract_existing_property_tests(parsed_tests) do
    parsed_tests
    |> Enum.filter(fn test ->
      test_content = build_test_content(test)
      String.contains?(test_content, "property") or
      String.contains?(test_content, "StreamData") or
      String.contains?(test_content, "check all")
    end)
    |> Enum.map(& &1.name)
  end

  defp extract_parser_opportunities(parsed_tests) do
    parsed_tests
    |> Enum.flat_map(fn test ->
      test_content = build_test_content(test)

      @parser_transformation_patterns
      |> Enum.take(8)  # Take only parser patterns
      |> Enum.flat_map(fn pattern ->
        Regex.scan(pattern, test_content, capture: :all_but_first)
        |> List.flatten()
      end)
    end)
    |> Enum.uniq()
  end

  defp extract_transformation_opportunities(parsed_tests) do
    parsed_tests
    |> Enum.flat_map(fn test ->
      test_content = build_test_content(test)

      @parser_transformation_patterns
      |> Enum.drop(8)  # Take only transformation patterns
      |> Enum.flat_map(fn pattern ->
        Regex.scan(pattern, test_content, capture: :all_but_first)
        |> List.flatten()
      end)
    end)
    |> Enum.uniq()
  end

  defp extract_tested_function_names(property_tests) do
    # Extract function names that are already covered by property tests
    property_tests
    |> Enum.flat_map(fn test_name ->
      # Simple heuristic: extract likely function names from test names
      test_name
      |> String.split(~r/[^a-z_]/)
      |> Enum.filter(&(String.length(&1) > 3))
    end)
    |> Enum.uniq()
  end

  defp generate_liveview_recommendations(untested_interactions, coverage) do
    recommendations = []

    # Add recommendations for low coverage
    recommendations = if coverage < 70.0 do
      [%Recommendation{
        type: :add_test,
        priority: :high,
        title: "Improve LiveView interaction test coverage",
        description: "LiveView interaction coverage is #{Float.round(coverage, 1)}%. Consider adding tests for untested interactions.",
        affected_files: [],
        estimated_effort: :medium,
        justification: "Low LiveView interaction coverage indicates potential gaps in user interaction testing."
      } | recommendations]
    else
      recommendations
    end

    # Add specific recommendations for untested interactions
    if length(untested_interactions) > 0 do
      [%Recommendation{
        type: :add_test,
        priority: :medium,
        title: "Add tests for untested LiveView interactions",
        description: "Found #{length(untested_interactions)} untested LiveView interactions that should be covered.",
        affected_files: [],
        estimated_effort: :medium,
        justification: "Untested LiveView interactions may lead to undetected bugs in user interface behavior."
      } | recommendations]
    else
      recommendations
    end
  end

  defp generate_validation_coverage_gaps(untested_validations) do
    untested_validations
    |> Enum.map(fn validation ->
      %CoverageGap{
        module_name: "Form Validation",
        function_name: validation,
        gap_type: :untested_validation,
        priority: :high,
        description: "Form validation '#{validation}' lacks test coverage",
        suggested_test_type: "unit test with valid/invalid inputs"
      }
    end)
  end

  defp generate_component_coverage_gaps(untested_components) do
    untested_components
    |> Enum.map(fn component ->
      %CoverageGap{
        module_name: "Phoenix Component",
        function_name: component,
        gap_type: :untested_component,
        priority: :medium,
        description: "Phoenix component '#{component}' lacks interaction testing",
        suggested_test_type: "component test with render_component/2"
      }
    end)
  end

  defp generate_property_test_recommendations(untested_parsers, untested_transformations) do
    recommendations = []

    # Add parser recommendations
    recommendations = if length(untested_parsers) > 0 do
      [%Recommendation{
        type: :add_test,
        priority: :high,
        title: "Add property tests for parsers",
        description: "Found #{length(untested_parsers)} parser functions that would benefit from property-based testing.",
        affected_files: [],
        estimated_effort: :medium,
        justification: "Parser functions are prone to edge case bugs that property-based testing can effectively catch."
      } | recommendations]
    else
      recommendations
    end

    # Add transformation recommendations
    if length(untested_transformations) > 0 do
      [%Recommendation{
        type: :add_test,
        priority: :medium,
        title: "Add property tests for transformations",
        description: "Found #{length(untested_transformations)} transformation functions that would benefit from property-based testing.",
        affected_files: [],
        estimated_effort: :medium,
        justification: "Data transformation functions benefit from property-based testing to ensure correctness across input ranges."
      } | recommendations]
    else
      recommendations
    end
  end

  defp extract_validation_name(pattern, match) do
    # Extract validation name from regex match
    case match do
      [full_match | _] when is_binary(full_match) ->
        cond do
          String.contains?(full_match, "validate_required") -> "validate_required"
          String.contains?(full_match, "validate_length") -> "validate_length"
          String.contains?(full_match, "validate_format") -> "validate_format"
          String.contains?(full_match, "validate_number") -> "validate_number"
          String.contains?(full_match, "validate_inclusion") -> "validate_inclusion"
          String.contains?(full_match, "validate_exclusion") -> "validate_exclusion"
          String.contains?(full_match, "validate_confirmation") -> "validate_confirmation"
          String.contains?(full_match, "validate_acceptance") -> "validate_acceptance"
          String.contains?(full_match, "validate_subset") -> "validate_subset"
          String.contains?(full_match, "validate_change") -> "validate_change"
          true -> nil
        end
      _ -> nil
    end
  end

  defp calculate_overall_phoenix_coverage(coverage_scores) do
    valid_scores = Enum.filter(coverage_scores, &is_number/1)

    if length(valid_scores) > 0 do
      Enum.sum(valid_scores) / length(valid_scores)
    else
      0.0
    end
  end
end
