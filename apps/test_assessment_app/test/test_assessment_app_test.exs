defmodule TestAssessmentAppTest do
  use ExUnit.Case, async: true

  alias TestAssessmentApp.{
    TestFile,
    ParsedTest,
    TestCategory,
    CoverageReport,
    AssessmentReport
  }

  describe "core data structures" do
    test "TestFile struct can be created" do
      test_file = %TestFile{
        path: "/path/to/test.exs",
        app_name: "my_app",
        relative_path: "test/my_test.exs",
        size: 1024,
        last_modified: DateTime.utc_now()
      }

      assert test_file.path == "/path/to/test.exs"
      assert test_file.app_name == "my_app"
    end

    test "ParsedTest struct can be created" do
      parsed_test = %ParsedTest{
        name: "test example",
        file_path: "/path/to/test.exs",
        line_number: 10,
        test_type: :test,
        setup_blocks: ["setup do"],
        assertions: ["assert true"],
        dependencies: ["MyModule"],
        complexity_score: 2.5
      }

      assert parsed_test.name == "test example"
      assert parsed_test.test_type == :test
      assert parsed_test.complexity_score == 2.5
    end

    test "TestCategory struct can be created" do
      category = %TestCategory{
        primary_type: :unit,
        secondary_types: [:integration],
        confidence_scores: %{unit: 0.8, integration: 0.2},
        focus_areas: ["authentication", "validation"]
      }

      assert category.primary_type == :unit
      assert category.secondary_types == [:integration]
    end

    test "CoverageReport struct can be created" do
      report = %CoverageReport{
        total_lines: 1000,
        covered_lines: 800,
        coverage_percentage: 80.0,
        uncovered_functions: ["MyModule.uncovered_function/1"],
        test_coverage_map: %{"MyModule" => ["test_function"]}
      }

      assert report.total_lines == 1000
      assert report.coverage_percentage == 80.0
    end

    test "AssessmentReport struct can be created" do
      report = %AssessmentReport{
        summary: nil,
        test_categories: %{},
        redundancy_findings: [],
        coverage_gaps: [],
        config_issues: [],
        recommendations: [],
        phoenix_analysis: %{},
        generated_at: DateTime.utc_now()
      }

      assert %DateTime{} = report.generated_at
      assert report.test_categories == %{}
    end
  end

  describe "assess_test_suite/2" do
    test "assess_test_suite handles invalid path gracefully" do
      # Test with a non-existent path - should still return a report with config issues
      result = TestAssessmentApp.assess_test_suite("/fake/path")

      assert {:ok, report} = result
      assert %AssessmentReport{} = report
    end
  end

  describe "validate_umbrella_project/1" do
    test "validate_umbrella_project returns error for non-existent path" do
      assert {:error, :path_not_found} =
               TestAssessmentApp.validate_umbrella_project("/non/existent/path")
    end

    test "validate_umbrella_project handles empty path" do
      assert {:error, :path_not_found} = TestAssessmentApp.validate_umbrella_project("")
    end

    test "validate_umbrella_project handles nil path" do
      assert_raise FunctionClauseError, fn ->
        TestAssessmentApp.validate_umbrella_project(nil)
      end
    end
  end
end
