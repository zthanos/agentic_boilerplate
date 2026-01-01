defmodule AgentCore.TestAssessment.ReportGeneratorTest do
  use ExUnit.Case, async: true

  alias AgentCore.TestAssessment.{
    ReportGenerator,
    AssessmentReport,
    ReportSummary,
    TestCategory,
    RedundancyFinding,
    CoverageGap,
    ConfigIssue,
    Recommendation
  }

  describe "generate_report/1" do
    test "generates comprehensive report with all sections" do
      analysis_results = %{
        test_categories: %{
          "test_user_creation" => %TestCategory{
            primary_type: :unit,
            secondary_types: [],
            confidence_scores: %{unit: 0.9},
            focus_areas: ["user_management"]
          }
        },
        redundancy_findings: [
          %RedundancyFinding{
            test_names: ["test_user_creation", "test_create_user"],
            redundancy_type: :similar_logic,
            confidence_score: 0.85,
            recommended_action: "Keep test_user_creation, remove test_create_user",
            justification: "Both tests exercise identical code paths with similar assertions"
          }
        ],
        coverage_gaps: [
          %CoverageGap{
            module_name: "UserService",
            function_name: "delete_user",
            gap_type: :untested_function,
            priority: :high,
            description: "Critical user deletion function has no test coverage",
            suggested_test_type: "unit test"
          }
        ],
        config_issues: [
          %ConfigIssue{
            app_name: "user_app",
            file_path: "config/test.exs",
            issue_type: :missing_dependency,
            severity: :warning,
            description: "Missing test database configuration",
            suggested_fix: "Add test database config to test.exs"
          }
        ],
        recommendations: [
          %Recommendation{
            type: :add_test,
            priority: :high,
            title: "Add tests for user deletion",
            description: "Critical functionality lacks test coverage",
            affected_files: ["lib/user_service.ex"],
            estimated_effort: :medium,
            justification: "User deletion is a critical operation that should be thoroughly tested"
          }
        ],
        parsed_tests: [%{name: "test_user_creation"}, %{name: "test_create_user"}],
        test_files: [%{path: "test/user_test.exs"}],
        apps_analyzed: 1
      }

      report = ReportGenerator.generate_report(analysis_results)

      assert %AssessmentReport{} = report
      assert report.summary.total_tests == 2
      assert report.summary.total_test_files == 1
      assert report.summary.apps_analyzed == 1
      assert report.summary.redundant_tests_found == 1
      assert report.summary.coverage_gaps_found == 1
      assert report.summary.config_issues_found == 1
      assert report.summary.overall_score < 100.0
      assert %DateTime{} = report.generated_at

      assert map_size(report.test_categories) == 1
      assert length(report.redundancy_findings) == 1
      assert length(report.coverage_gaps) == 1
      assert length(report.config_issues) == 1
      assert length(report.recommendations) == 1
    end

    test "handles empty analysis results" do
      analysis_results = %{}

      report = ReportGenerator.generate_report(analysis_results)

      assert %AssessmentReport{} = report
      assert report.summary.total_tests == 0
      assert report.summary.total_test_files == 0
      assert report.summary.apps_analyzed == 0
      assert report.summary.redundant_tests_found == 0
      assert report.summary.coverage_gaps_found == 0
      assert report.summary.config_issues_found == 0
      assert report.summary.overall_score == 100.0

      assert report.test_categories == %{}
      assert report.redundancy_findings == []
      assert report.coverage_gaps == []
      assert report.config_issues == []
      assert report.recommendations == []
    end

    test "calculates overall score based on issues found" do
      # Test with many issues - should have lower score
      analysis_results_with_issues = %{
        redundancy_findings: [%RedundancyFinding{}, %RedundancyFinding{}], # 2 * 2.0 = 4.0 penalty
        coverage_gaps: [%CoverageGap{}, %CoverageGap{}, %CoverageGap{}], # 3 * 1.5 = 4.5 penalty
        config_issues: [%ConfigIssue{}], # 1 * 3.0 = 3.0 penalty
        parsed_tests: [],
        test_files: [],
        apps_analyzed: 1
      }

      report_with_issues = ReportGenerator.generate_report(analysis_results_with_issues)
      expected_score = 100.0 - 4.0 - 4.5 - 3.0 # = 88.5
      assert report_with_issues.summary.overall_score == expected_score

      # Test with no issues - should have perfect score
      analysis_results_clean = %{
        redundancy_findings: [],
        coverage_gaps: [],
        config_issues: [],
        parsed_tests: [],
        test_files: [],
        apps_analyzed: 1
      }

      report_clean = ReportGenerator.generate_report(analysis_results_clean)
      assert report_clean.summary.overall_score == 100.0
    end
  end

  describe "organize_by_categories/1" do
    test "organizes test categories by primary type" do
      report = %AssessmentReport{
        summary: %ReportSummary{},
        test_categories: %{
          "test_unit_1" => %TestCategory{primary_type: :unit, secondary_types: [], confidence_scores: %{}, focus_areas: []},
          "test_unit_2" => %TestCategory{primary_type: :unit, secondary_types: [], confidence_scores: %{}, focus_areas: []},
          "test_integration_1" => %TestCategory{primary_type: :integration, secondary_types: [], confidence_scores: %{}, focus_areas: []}
        },
        redundancy_findings: [
          %RedundancyFinding{confidence_score: 0.7},
          %RedundancyFinding{confidence_score: 0.9},
          %RedundancyFinding{confidence_score: 0.5}
        ],
        coverage_gaps: [
          %CoverageGap{priority: :low},
          %CoverageGap{priority: :critical},
          %CoverageGap{priority: :high}
        ],
        config_issues: [],
        recommendations: [
          %Recommendation{priority: :medium},
          %Recommendation{priority: :critical},
          %Recommendation{priority: :low}
        ],
        generated_at: DateTime.utc_now()
      }

      organized_report = ReportGenerator.organize_by_categories(report)

      # Test categories should be grouped by primary type
      assert Map.has_key?(organized_report.test_categories, :unit)
      assert Map.has_key?(organized_report.test_categories, :integration)
      assert map_size(organized_report.test_categories[:unit]) == 2
      assert map_size(organized_report.test_categories[:integration]) == 1

      # Redundancy findings should be sorted by confidence score (highest first)
      confidence_scores = Enum.map(organized_report.redundancy_findings, & &1.confidence_score)
      assert confidence_scores == [0.9, 0.7, 0.5]

      # Coverage gaps should be sorted by priority (critical first)
      gap_priorities = Enum.map(organized_report.coverage_gaps, & &1.priority)
      assert gap_priorities == [:critical, :high, :low]

      # Recommendations should be sorted by priority (critical first)
      rec_priorities = Enum.map(organized_report.recommendations, & &1.priority)
      assert rec_priorities == [:critical, :medium, :low]
    end
  end

  describe "export_report/2" do
    setup do
      report = %AssessmentReport{
        summary: %ReportSummary{
          total_tests: 5,
          total_test_files: 3,
          apps_analyzed: 2,
          redundant_tests_found: 1,
          coverage_gaps_found: 2,
          config_issues_found: 1,
          overall_score: 85.5
        },
        test_categories: %{
          unit: %{
            "test_user_creation" => %TestCategory{
              primary_type: :unit,
              secondary_types: [],
              confidence_scores: %{unit: 0.9},
              focus_areas: ["user_management"]
            }
          }
        },
        redundancy_findings: [
          %RedundancyFinding{
            test_names: ["test_a", "test_b"],
            redundancy_type: :similar_logic,
            confidence_score: 0.85,
            recommended_action: "Keep test_a",
            justification: "Test A has better assertions"
          }
        ],
        coverage_gaps: [
          %CoverageGap{
            module_name: "UserService",
            function_name: "delete_user",
            gap_type: :untested_function,
            priority: :high,
            description: "No test coverage",
            suggested_test_type: "unit test"
          }
        ],
        config_issues: [
          %ConfigIssue{
            app_name: "user_app",
            file_path: "config/test.exs",
            issue_type: :missing_dependency,
            severity: :warning,
            description: "Missing config",
            suggested_fix: "Add config"
          }
        ],
        recommendations: [
          %Recommendation{
            type: :add_test,
            priority: :high,
            title: "Add user tests",
            description: "Need more tests",
            affected_files: ["lib/user.ex"],
            estimated_effort: :medium,
            justification: "Critical functionality"
          }
        ],
        generated_at: ~U[2024-01-01 12:00:00Z]
      }

      {:ok, report: report}
    end

    test "exports to text format", %{report: report} do
      text_output = ReportGenerator.export_report(report, :text)

      assert is_binary(text_output)
      assert String.contains?(text_output, "# Test Assessment Report")
      assert String.contains?(text_output, "Generated: 2024-01-01 12:00:00Z")
      assert String.contains?(text_output, "Total Tests: 5")
      assert String.contains?(text_output, "Overall Score: 85.5/100")
      assert String.contains?(text_output, "## Summary")
      assert String.contains?(text_output, "## Test Categories")
      assert String.contains?(text_output, "## Redundancy Findings")
      assert String.contains?(text_output, "## Coverage Gaps")
      assert String.contains?(text_output, "## Configuration Issues")
      assert String.contains?(text_output, "## Recommendations")
      assert String.contains?(text_output, "UserService.delete_user")
      assert String.contains?(text_output, "test_a, test_b")
    end

    test "exports to JSON format", %{report: report} do
      json_output = ReportGenerator.export_report(report, :json)

      assert is_binary(json_output)

      # Parse JSON to verify structure
      {:ok, parsed} = Jason.decode(json_output)

      assert Map.has_key?(parsed, "summary")
      assert Map.has_key?(parsed, "test_categories")
      assert Map.has_key?(parsed, "redundancy_findings")
      assert Map.has_key?(parsed, "coverage_gaps")
      assert Map.has_key?(parsed, "config_issues")
      assert Map.has_key?(parsed, "recommendations")
      assert Map.has_key?(parsed, "generated_at")

      assert parsed["summary"]["total_tests"] == 5
      assert parsed["summary"]["overall_score"] == 85.5
      assert length(parsed["redundancy_findings"]) == 1
      assert length(parsed["coverage_gaps"]) == 1
      assert length(parsed["config_issues"]) == 1
      assert length(parsed["recommendations"]) == 1
    end

    test "exports to HTML format", %{report: report} do
      html_output = ReportGenerator.export_report(report, :html)

      assert is_binary(html_output)
      assert String.contains?(html_output, "<!DOCTYPE html>")
      assert String.contains?(html_output, "<title>Test Assessment Report</title>")
      assert String.contains?(html_output, "<h1>Test Assessment Report</h1>")
      assert String.contains?(html_output, "Generated: 2024-01-01 12:00:00Z")
      assert String.contains?(html_output, "<h2>Summary</h2>")
      assert String.contains?(html_output, "<h2>Test Categories</h2>")
      assert String.contains?(html_output, "<h2>Redundancy Findings")
      assert String.contains?(html_output, "<h2>Coverage Gaps")
      assert String.contains?(html_output, "<h2>Configuration Issues")
      assert String.contains?(html_output, "<h2>Recommendations")
      assert String.contains?(html_output, "summary-grid")
      assert String.contains?(html_output, "priority-high")
      assert String.contains?(html_output, "UserService.delete_user")
      assert String.contains?(html_output, "test_a, test_b")
    end
  end
end
