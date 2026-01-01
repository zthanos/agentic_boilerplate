defmodule AgentCore.TestAssessment.RecommendationEngine do
  @moduledoc """
  Module responsible for generating actionable recommendations for test suite improvement.

  This module analyzes test assessment results and generates prioritized, actionable
  recommendations for improving test quality, removing redundancies, filling coverage
  gaps, and modernizing test practices.
  """

  alias AgentCore.TestAssessment.{
    Recommendation,
    ParsedTest
  }

  alias AgentCore.TestAssessment.RedundancyFinding
  alias AgentCore.TestAssessment.CoverageGap
  alias AgentCore.TestAssessment.ConfigIssue

  @doc """
  Generates improvement recommendations based on analysis results.

  Takes a comprehensive analysis results map and generates specific, actionable
  recommendations for test suite improvement.
  """
  @spec generate_recommendations(map()) :: [Recommendation.t()]
  def generate_recommendations(analysis_results) do
    recommendations = []

    # Generate recommendations from redundancy findings
    recommendations =
      case Map.get(analysis_results, :redundancy_findings, []) do
        [] -> recommendations
        findings -> recommendations ++ generate_redundancy_recommendations(findings)
      end

    # Generate recommendations from coverage gaps
    recommendations =
      case Map.get(analysis_results, :coverage_gaps, []) do
        [] -> recommendations
        gaps -> recommendations ++ generate_coverage_recommendations(gaps)
      end

    # Generate recommendations from config issues
    recommendations =
      case Map.get(analysis_results, :config_issues, []) do
        [] -> recommendations
        issues -> recommendations ++ generate_config_recommendations(issues)
      end

    # Generate recommendations from parsed tests
    recommendations =
      case Map.get(analysis_results, :parsed_tests, []) do
        [] ->
          recommendations

        tests ->
          recommendations ++
            suggest_refactoring(tests) ++
            recommend_modern_practices(tests) ++
            suggest_performance_optimizations(tests)
      end

    # Prioritize and return recommendations
    prioritize_action_items(recommendations)
  end

  @doc """
  Suggests refactoring approaches for test quality issues.

  Analyzes parsed tests to identify quality issues and suggests specific
  refactoring approaches to improve test maintainability and reliability.
  """
  @spec suggest_refactoring([ParsedTest.t()]) :: [Recommendation.t()]
  def suggest_refactoring(parsed_tests) do
    parsed_tests
    |> Enum.flat_map(&analyze_test_quality/1)
    |> Enum.uniq_by(fn rec -> {rec.title, rec.affected_files} end)
  end

  @doc """
  Recommends modern Phoenix testing practices for outdated patterns.

  Identifies outdated testing patterns and suggests modern Phoenix testing
  practices to improve test quality and maintainability.
  """
  @spec recommend_modern_practices([ParsedTest.t()]) :: [Recommendation.t()]
  def recommend_modern_practices(parsed_tests) do
    parsed_tests
    |> Enum.flat_map(&detect_outdated_patterns/1)
    |> Enum.uniq_by(fn rec -> {rec.title, rec.affected_files} end)
  end

  @doc """
  Suggests performance optimization strategies for slow tests.

  Analyzes test complexity and patterns to identify potential performance
  issues and suggests optimization strategies.
  """
  @spec suggest_performance_optimizations([ParsedTest.t()]) :: [Recommendation.t()]
  def suggest_performance_optimizations(parsed_tests) do
    parsed_tests
    |> Enum.filter(&is_potentially_slow_test?/1)
    |> Enum.flat_map(&suggest_test_optimizations/1)
    |> Enum.uniq_by(fn rec -> {rec.title, rec.affected_files} end)
  end

  @doc """
  Prioritizes action items with effort estimation.

  Sorts recommendations by priority and impact, ensuring critical issues
  are addressed first while considering implementation effort.
  """
  @spec prioritize_action_items([Recommendation.t()]) :: [Recommendation.t()]
  def prioritize_action_items(recommendations) do
    recommendations
    |> Enum.sort_by(&priority_score/1, :desc)
  end

  # Private helper functions

  defp generate_redundancy_recommendations(findings) do
    Enum.map(findings, fn finding ->
      %Recommendation{
        type: :remove_test,
        priority: determine_redundancy_priority(finding),
        title: "Remove redundant test: #{format_test_names(finding.test_names)}",
        description: "#{finding.recommended_action}. #{finding.justification}",
        affected_files: extract_file_paths_from_test_names(finding.test_names),
        estimated_effort: :small,
        justification: finding.justification
      }
    end)
  end

  defp generate_coverage_recommendations(gaps) do
    Enum.map(gaps, fn gap ->
      %Recommendation{
        type: :add_test,
        priority: gap.priority,
        title:
          "Add test for #{gap.module_name}#{if gap.function_name, do: ".#{gap.function_name}", else: ""}",
        description: "#{gap.description}. Consider adding #{gap.suggested_test_type}.",
        affected_files: [infer_test_file_path(gap.module_name)],
        estimated_effort: determine_test_effort(gap.gap_type),
        justification: "Missing test coverage for #{gap_type_description(gap.gap_type)}"
      }
    end)
  end

  defp generate_config_recommendations(issues) do
    Enum.map(issues, fn issue ->
      %Recommendation{
        type: :update_config,
        priority: config_severity_to_priority(issue.severity),
        title: "Fix #{issue.issue_type} in #{issue.app_name}",
        description: "#{issue.description}. #{issue.suggested_fix}",
        affected_files: [issue.file_path],
        estimated_effort: :small,
        justification: "Configuration issue affects test reliability and consistency"
      }
    end)
  end

  defp analyze_test_quality(test) do
    recommendations = []

    # Check for overly complex tests
    recommendations =
      if test.complexity_score > 10.0 do
        [create_complexity_recommendation(test) | recommendations]
      else
        recommendations
      end

    # Check for tests with too many assertions
    recommendations =
      if length(test.assertions) > 5 do
        [create_assertion_recommendation(test) | recommendations]
      else
        recommendations
      end

    # Check for tests with excessive setup
    recommendations =
      if length(test.setup_blocks) > 3 do
        [create_setup_recommendation(test) | recommendations]
      else
        recommendations
      end

    recommendations
  end

  defp detect_outdated_patterns(test) do
    recommendations = []

    # Check for deprecated Phoenix test patterns
    recommendations =
      if has_deprecated_phoenix_patterns?(test) do
        [create_modernization_recommendation(test) | recommendations]
      else
        recommendations
      end

    # Check for old assertion patterns
    recommendations =
      if has_old_assertion_patterns?(test) do
        [create_assertion_modernization_recommendation(test) | recommendations]
      else
        recommendations
      end

    recommendations
  end

  defp is_potentially_slow_test?(test) do
    # High complexity score indicates potential performance issues
    # Many dependencies might indicate slow setup
    # Certain test types are typically slower
    test.complexity_score > 8.0 or
      length(test.dependencies) > 10 or
      test.test_type in [:integration, :end_to_end]
  end

  defp suggest_test_optimizations(test) do
    recommendations = []

    recommendations =
      if test.complexity_score > 8.0 do
        [create_performance_recommendation(test) | recommendations]
      else
        recommendations
      end

    recommendations =
      if length(test.dependencies) > 10 do
        [create_dependency_recommendation(test) | recommendations]
      else
        recommendations
      end

    recommendations
  end

  defp create_complexity_recommendation(test) do
    %Recommendation{
      type: :refactor_test,
      priority: :medium,
      title: "Simplify complex test: #{test.name}",
      description:
        "Test has high complexity score (#{test.complexity_score}). Consider breaking into smaller, focused tests.",
      affected_files: [test.file_path],
      estimated_effort: :medium,
      justification: "Complex tests are harder to maintain and debug when they fail"
    }
  end

  defp create_assertion_recommendation(test) do
    %Recommendation{
      type: :refactor_test,
      priority: :low,
      title: "Reduce assertions in test: #{test.name}",
      description:
        "Test has #{length(test.assertions)} assertions. Consider splitting into multiple focused tests.",
      affected_files: [test.file_path],
      estimated_effort: :small,
      justification: "Tests with many assertions are harder to understand and debug"
    }
  end

  defp create_setup_recommendation(test) do
    %Recommendation{
      type: :refactor_test,
      priority: :low,
      title: "Simplify test setup: #{test.name}",
      description:
        "Test has #{length(test.setup_blocks)} setup blocks. Consider extracting common setup to shared fixtures.",
      affected_files: [test.file_path],
      estimated_effort: :medium,
      justification: "Excessive setup makes tests harder to understand and maintain"
    }
  end

  defp create_modernization_recommendation(test) do
    %Recommendation{
      type: :modernize_pattern,
      priority: :medium,
      title: "Modernize Phoenix test patterns: #{test.name}",
      description:
        "Test uses deprecated Phoenix testing patterns. Update to use modern Phoenix 1.8+ practices.",
      affected_files: [test.file_path],
      estimated_effort: :small,
      justification: "Modern Phoenix patterns improve test reliability and maintainability"
    }
  end

  defp create_assertion_modernization_recommendation(test) do
    %Recommendation{
      type: :modernize_pattern,
      priority: :low,
      title: "Update assertion patterns: #{test.name}",
      description:
        "Test uses outdated assertion patterns. Consider using modern ExUnit assertions.",
      affected_files: [test.file_path],
      estimated_effort: :small,
      justification: "Modern assertion patterns provide better error messages and debugging"
    }
  end

  defp create_performance_recommendation(test) do
    %Recommendation{
      type: :refactor_test,
      priority: :medium,
      title: "Optimize test performance: #{test.name}",
      description:
        "Test has high complexity and may be slow. Consider optimizing setup, using mocks, or parallel execution.",
      affected_files: [test.file_path],
      estimated_effort: :medium,
      justification: "Slow tests impact development velocity and CI/CD pipeline performance"
    }
  end

  defp create_dependency_recommendation(test) do
    %Recommendation{
      type: :refactor_test,
      priority: :low,
      title: "Reduce test dependencies: #{test.name}",
      description:
        "Test has #{length(test.dependencies)} dependencies. Consider using mocks or test doubles to reduce coupling.",
      affected_files: [test.file_path],
      estimated_effort: :medium,
      justification: "Tests with many dependencies are fragile and slow"
    }
  end

  defp has_deprecated_phoenix_patterns?(test) do
    # Check for common deprecated patterns in assertions
    Enum.any?(test.assertions, fn assertion ->
      String.contains?(assertion, "Phoenix.View") or
        String.contains?(assertion, "live_redirect") or
        String.contains?(assertion, "live_patch") or
        String.contains?(assertion, "form_for")
    end)
  end

  defp has_old_assertion_patterns?(test) do
    # Check for old assertion patterns
    Enum.any?(test.assertions, fn assertion ->
      (String.contains?(assertion, "assert_receive") and
         not String.contains?(assertion, "assert_received")) or
        (String.contains?(assertion, "refute_receive") and
           not String.contains?(assertion, "refute_received"))
    end)
  end

  defp determine_redundancy_priority(finding) do
    case finding.confidence_score do
      score when score >= 0.9 -> :high
      score when score >= 0.7 -> :medium
      _ -> :low
    end
  end

  defp config_severity_to_priority(:critical), do: :critical
  defp config_severity_to_priority(:error), do: :high
  defp config_severity_to_priority(:warning), do: :medium

  defp determine_test_effort(:untested_function), do: :small
  defp determine_test_effort(:missing_edge_case), do: :small
  defp determine_test_effort(:missing_error_condition), do: :small
  defp determine_test_effort(:untested_component), do: :medium

  defp gap_type_description(:untested_function), do: "function without test coverage"
  defp gap_type_description(:missing_edge_case), do: "missing edge case testing"
  defp gap_type_description(:missing_error_condition), do: "missing error condition testing"
  defp gap_type_description(:untested_component), do: "untested component interactions"

  defp priority_score(recommendation) do
    base_score =
      case recommendation.priority do
        :critical -> 1000
        :high -> 100
        :medium -> 10
        :low -> 1
      end

    # Adjust score based on effort (prefer quick wins)
    effort_modifier =
      case recommendation.estimated_effort do
        :small -> 1.5
        :medium -> 1.0
        :large -> 0.7
      end

    base_score * effort_modifier
  end

  defp format_test_names(test_names) do
    case length(test_names) do
      1 -> hd(test_names)
      2 -> Enum.join(test_names, " and ")
      _ -> "#{hd(test_names)} and #{length(test_names) - 1} others"
    end
  end

  defp extract_file_paths_from_test_names(test_names) do
    # This is a simplified implementation - in practice, we'd need to track
    # the mapping between test names and file paths
    test_names
    |> Enum.map(fn name ->
      # Convert test name to likely file path
      name
      |> String.downcase()
      |> String.replace(" ", "_")
      |> then(&"test/#{&1}_test.exs")
    end)
    |> Enum.uniq()
  end

  defp infer_test_file_path(module_name) do
    # Convert module name to test file path
    module_name
    |> String.replace(".", "/")
    |> String.downcase()
    |> then(&"test/#{&1}_test.exs")
  end
end
