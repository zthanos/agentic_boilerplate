defmodule AgentCore.TestAssessment.RedundancyDetector do
  @moduledoc """
  Module responsible for detecting redundant tests in the test suite.
  """

  alias AgentCore.TestAssessment.{ParsedTest, RedundancyFinding, CoverageReport}

  @doc """
  Detects tests with redundant coverage patterns.

  Identifies tests that exercise identical code paths and flags them
  for potential removal or consolidation.
  """
  @spec detect_redundant_coverage([ParsedTest.t()], CoverageReport.t()) :: [RedundancyFinding.t()]
  def detect_redundant_coverage(parsed_tests, coverage_report) do
    # Group tests by their coverage patterns
    coverage_groups = group_tests_by_coverage(parsed_tests, coverage_report)

    # Find groups with multiple tests (redundant coverage)
    coverage_groups
    |> Enum.filter(fn {_coverage_pattern, tests} -> length(tests) > 1 end)
    |> Enum.map(fn {coverage_pattern, tests} ->
      test_names = Enum.map(tests, & &1.name)
      recommended_test = recommend_best_test(tests)

      %RedundancyFinding{
        test_names: test_names,
        redundancy_type: :identical_coverage,
        confidence_score: calculate_coverage_confidence(coverage_pattern, tests),
        recommended_action: "Keep '#{recommended_test.name}', consider removing others",
        justification: "These tests exercise identical code paths: #{Enum.join(coverage_pattern, ", ")}"
      }
    end)
  end

  @doc """
  Detects tests with similar logic patterns.
  """
  @spec detect_similar_logic([ParsedTest.t()]) :: [RedundancyFinding.t()]
  def detect_similar_logic(parsed_tests) do
    # Group tests by similar assertion patterns
    assertion_groups = group_tests_by_assertions(parsed_tests)

    # Find groups with similar logic patterns
    assertion_groups
    |> Enum.filter(fn {_pattern, tests} -> length(tests) > 1 end)
    |> Enum.map(fn {assertion_pattern, tests} ->
      test_names = Enum.map(tests, & &1.name)
      recommended_test = recommend_best_test(tests)

      %RedundancyFinding{
        test_names: test_names,
        redundancy_type: :similar_logic,
        confidence_score: calculate_similarity_confidence(assertion_pattern, tests),
        recommended_action: "Keep '#{recommended_test.name}', review others for consolidation",
        justification: "These tests have similar assertion patterns and may be testing the same logic"
      }
    end)
  end

  @doc """
  Recommends which tests to keep based on quality metrics.
  """
  @spec recommend_tests_to_keep([ParsedTest.t()]) :: [String.t()]
  def recommend_tests_to_keep(redundant_tests) do
    redundant_tests
    |> Enum.sort_by(&calculate_test_quality_score/1, :desc)
    |> Enum.take(1)
    |> Enum.map(& &1.name)
  end

  @doc """
  Handles Phoenix LiveView specific redundancy detection.
  """
  @spec handle_liveview_redundancy([ParsedTest.t()]) :: [RedundancyFinding.t()]
  def handle_liveview_redundancy(liveview_tests) do
    # Filter out tests that are LiveView-specific
    liveview_specific_tests = Enum.filter(liveview_tests, &is_liveview_test?/1)

    # Group by interaction patterns rather than just coverage
    interaction_groups = group_liveview_by_interactions(liveview_specific_tests)

    # Only flag as redundant if they have identical interaction patterns
    interaction_groups
    |> Enum.filter(fn {_pattern, tests} -> length(tests) > 1 end)
    |> Enum.map(fn {interaction_pattern, tests} ->
      test_names = Enum.map(tests, & &1.name)
      recommended_test = recommend_best_test(tests)

      %RedundancyFinding{
        test_names: test_names,
        redundancy_type: :duplicate_assertions,
        confidence_score: 0.8, # Lower confidence for LiveView tests
        recommended_action: "Keep '#{recommended_test.name}', review others for different interaction patterns",
        justification: "These LiveView tests have identical interaction patterns: #{interaction_pattern}"
      }
    end)
  end

  # Private helper functions

  defp group_tests_by_coverage(parsed_tests, coverage_report) do
    parsed_tests
    |> Enum.group_by(fn test ->
      # Get coverage pattern for this test from the coverage report
      Map.get(coverage_report.test_coverage_map, test.name, [])
      |> Enum.sort()
    end)
  end

  defp group_tests_by_assertions(parsed_tests) do
    parsed_tests
    |> Enum.group_by(fn test ->
      # Create a pattern from assertions, normalized for comparison
      # Focus on the structure rather than exact content
      test.assertions
      |> Enum.map(&extract_assertion_pattern/1)
      |> Enum.sort()
    end)
  end

  defp group_liveview_by_interactions(liveview_tests) do
    liveview_tests
    |> Enum.group_by(fn test ->
      # Extract interaction patterns from LiveView tests
      extract_liveview_interactions(test)
    end)
  end

  defp normalize_assertion(assertion) do
    assertion
    |> String.downcase()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp extract_assertion_pattern(assertion) do
    # Extract structural patterns from assertions, ignoring specific values
    assertion
    |> String.downcase()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    # Replace specific field names with generic patterns
    |> String.replace(~r/\.name\b/, ".field")
    |> String.replace(~r/\.email\b/, ".field")
    |> String.replace(~r/\.id\b/, ".field")
    # Replace specific values with placeholders
    |> String.replace(~r/"[^"]*"/, "\"value\"")
    |> String.replace(~r/== \w+/, "== value")
    |> String.replace(~r/!= \w+/, "!= value")
  end

  defp extract_liveview_interactions(test) do
    # Look for LiveView-specific patterns in assertions
    liveview_patterns = [
      "render_click",
      "render_submit",
      "render_change",
      "has_element",
      "element",
      "phx-click",
      "phx-submit",
      "phx-change"
    ]

    test.assertions
    |> Enum.filter(fn assertion ->
      Enum.any?(liveview_patterns, &String.contains?(assertion, &1))
    end)
    |> Enum.map(&normalize_assertion/1)
    |> Enum.sort()
    |> Enum.join("|")
  end

  defp is_liveview_test?(test) do
    liveview_indicators = [
      "LiveViewTest",
      "render_click",
      "render_submit",
      "render_change",
      "has_element",
      "element"
    ]

    test_content = Enum.join([test.name | test.assertions], " ")
    Enum.any?(liveview_indicators, &String.contains?(test_content, &1))
  end

  defp recommend_best_test(tests) do
    tests
    |> Enum.max_by(&calculate_test_quality_score/1)
  end

  defp calculate_test_quality_score(test) do
    # Quality score based on multiple factors
    base_score = test.complexity_score || 1.0
    assertion_count = length(test.assertions)
    setup_complexity = length(test.setup_blocks)

    # Higher score for more comprehensive tests
    base_score + (assertion_count * 0.1) + (setup_complexity * 0.05)
  end

  defp calculate_coverage_confidence(coverage_pattern, tests) do
    # Higher confidence when coverage patterns are identical and substantial
    pattern_size = length(coverage_pattern)
    test_count = length(tests)

    base_confidence = if pattern_size > 0, do: 0.7, else: 0.3

    # Increase confidence with more substantial coverage
    coverage_bonus = min(pattern_size * 0.05, 0.2)

    # Slight increase with more redundant tests
    redundancy_bonus = min((test_count - 1) * 0.05, 0.1)

    min(base_confidence + coverage_bonus + redundancy_bonus, 1.0)
  end

  defp calculate_similarity_confidence(assertion_pattern, tests) do
    # Lower confidence for similar logic as it's more subjective
    pattern_complexity = length(assertion_pattern)
    test_count = length(tests)

    base_confidence = if pattern_complexity > 1, do: 0.6, else: 0.4

    # Increase confidence with more similar assertions
    similarity_bonus = min(pattern_complexity * 0.03, 0.15)

    # Slight increase with more similar tests
    redundancy_bonus = min((test_count - 1) * 0.03, 0.1)

    min(base_confidence + similarity_bonus + redundancy_bonus, 0.85)
  end
end
