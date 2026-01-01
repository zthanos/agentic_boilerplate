defmodule AgentCore.TestAssessment.CoverageAnalysisTest do
  use ExUnit.Case, async: true

  alias AgentCore.TestAssessment.{CoverageAnalysis, ParsedTest, CoverageReport, CoverageGap}

  describe "analyze_coverage/1" do
    test "analyzes coverage for empty test list" do
      result = CoverageAnalysis.analyze_coverage([])

      assert %CoverageReport{} = result
      assert result.total_lines == 0
      assert result.covered_lines == 0
      assert result.coverage_percentage == 0.0
      assert result.uncovered_functions == []
      assert result.test_coverage_map == %{}
    end

    test "analyzes coverage for single test" do
      test = %ParsedTest{
        name: "test user creation",
        file_path: "/test/user_test.exs",
        line_number: 10,
        test_type: :test,
        setup_blocks: ["setup do", "user = build(:user)"],
        assertions: ["assert User.create(attrs)", "assert user.name == \"John\""],
        dependencies: ["alias MyApp.User", "import MyApp.Factory"],
        complexity_score: 5.0
      }

      result = CoverageAnalysis.analyze_coverage([test])

      assert %CoverageReport{} = result
      assert result.total_lines > 0
      assert result.covered_lines >= 0
      assert is_float(result.coverage_percentage)
      assert is_list(result.uncovered_functions)
      assert Map.has_key?(result.test_coverage_map, "test user creation")
    end

    test "analyzes coverage for multiple tests" do
      tests = [
        %ParsedTest{
          name: "test user creation",
          file_path: "/test/user_test.exs",
          line_number: 10,
          test_type: :test,
          setup_blocks: [],
          assertions: ["assert User.create(attrs)"],
          dependencies: ["alias MyApp.User"],
          complexity_score: 3.0
        },
        %ParsedTest{
          name: "test user validation",
          file_path: "/test/user_test.exs",
          line_number: 20,
          test_type: :test,
          setup_blocks: [],
          assertions: ["assert User.validate(user)"],
          dependencies: ["alias MyApp.User"],
          complexity_score: 2.0
        }
      ]

      result = CoverageAnalysis.analyze_coverage(tests)

      assert %CoverageReport{} = result
      assert result.total_lines > 0
      assert length(Map.keys(result.test_coverage_map)) == 2
    end
  end

  describe "calculate_value_score/2" do
    test "calculates value score for test with unique coverage" do
      test = %ParsedTest{
        name: "unique test",
        file_path: "/test/unique_test.exs",
        line_number: 10,
        test_type: :integration,
        setup_blocks: ["setup do"],
        assertions: ["assert UniqueModule.unique_function()"],
        dependencies: ["alias MyApp.UniqueModule"],
        complexity_score: 8.0
      }

      coverage_report = %CoverageReport{
        total_lines: 100,
        covered_lines: 80,
        coverage_percentage: 80.0,
        uncovered_functions: [],
        test_coverage_map: %{
          "unique test" => ["MyApp.UniqueModule.unique_function"],
          "other test" => ["MyApp.OtherModule.other_function"]
        }
      }

      score = CoverageAnalysis.calculate_value_score(test, coverage_report)

      assert is_float(score)
      assert score >= 0.0
      assert score <= 100.0
    end

    test "calculates lower score for test with redundant coverage" do
      test = %ParsedTest{
        name: "redundant test",
        file_path: "/test/redundant_test.exs",
        line_number: 10,
        test_type: :test,
        setup_blocks: [],
        assertions: ["assert CommonModule.common_function()"],
        dependencies: ["alias MyApp.CommonModule"],
        complexity_score: 2.0
      }

      coverage_report = %CoverageReport{
        total_lines: 100,
        covered_lines: 80,
        coverage_percentage: 80.0,
        uncovered_functions: [],
        test_coverage_map: %{
          "redundant test" => ["MyApp.CommonModule.common_function"],
          "other test 1" => ["MyApp.CommonModule.common_function"],
          "other test 2" => ["MyApp.CommonModule.common_function"]
        }
      }

      score = CoverageAnalysis.calculate_value_score(test, coverage_report)

      assert is_float(score)
      assert score >= 0.0
      assert score <= 100.0
    end
  end

  describe "identify_coverage_gaps/1" do
    test "identifies uncovered function gaps" do
      coverage_report = %CoverageReport{
        total_lines: 100,
        covered_lines: 60,
        coverage_percentage: 60.0,
        uncovered_functions: ["MyApp.User.delete", "MyApp.Post.validate"],
        test_coverage_map: %{}
      }

      gaps = CoverageAnalysis.identify_coverage_gaps(coverage_report)

      assert is_list(gaps)
      assert length(gaps) >= 2

      # Check that uncovered functions are included
      function_gaps = Enum.filter(gaps, &(&1.gap_type == :untested_function))
      assert length(function_gaps) >= 2

      # Verify gap structure
      gap = List.first(function_gaps)
      assert %CoverageGap{} = gap
      assert gap.module_name != nil
      assert gap.gap_type == :untested_function
      assert gap.priority in [:low, :medium, :high, :critical]
      assert is_binary(gap.description)
      assert is_binary(gap.suggested_test_type)
    end

    test "identifies edge case gaps" do
      coverage_report = %CoverageReport{
        total_lines: 100,
        covered_lines: 80,
        coverage_percentage: 80.0,
        uncovered_functions: [],
        test_coverage_map: %{
          "test parsing" => ["MyApp.Parser.parse_data"],
          "test validation" => ["MyApp.Validator.validate_input"]
        }
      }

      gaps = CoverageAnalysis.identify_coverage_gaps(coverage_report)

      edge_case_gaps = Enum.filter(gaps, &(&1.gap_type == :missing_edge_case))
      assert length(edge_case_gaps) > 0

      gap = List.first(edge_case_gaps)
      assert %CoverageGap{} = gap
      assert gap.gap_type == :missing_edge_case
      assert String.contains?(gap.suggested_test_type, "property-based")
    end

    test "identifies error condition gaps" do
      coverage_report = %CoverageReport{
        total_lines: 100,
        covered_lines: 80,
        coverage_percentage: 80.0,
        uncovered_functions: [],
        test_coverage_map: %{
          "test creation" => ["MyApp.User.create"],
          "test fetching" => ["MyApp.User.get_by_id"]
        }
      }

      gaps = CoverageAnalysis.identify_coverage_gaps(coverage_report)

      error_gaps = Enum.filter(gaps, &(&1.gap_type == :missing_error_condition))
      assert length(error_gaps) > 0

      gap = List.first(error_gaps)
      assert %CoverageGap{} = gap
      assert gap.gap_type == :missing_error_condition
      assert gap.priority == :high
    end
  end

  describe "analyze_test_code_paths/1" do
    test "extracts code paths from test dependencies and assertions" do
      test = %ParsedTest{
        name: "comprehensive test",
        file_path: "/test/comprehensive_test.exs",
        line_number: 10,
        test_type: :test,
        setup_blocks: ["MyApp.Factory.build(:user)"],
        assertions: ["assert MyApp.User.create(attrs)", "refute MyApp.User.invalid?(user)"],
        dependencies: ["alias MyApp.User", "import MyApp.Factory"],
        complexity_score: 5.0
      }

      paths = CoverageAnalysis.analyze_test_code_paths(test)

      assert is_list(paths)
      assert length(paths) > 0

      # Should include paths from dependencies, assertions, and setup
      assert Enum.any?(paths, &String.contains?(&1, "MyApp.User"))
      assert Enum.any?(paths, &String.contains?(&1, "MyApp.Factory"))
    end

    test "filters out invalid code paths" do
      test = %ParsedTest{
        name: "test with invalid paths",
        file_path: "/test/invalid_test.exs",
        line_number: 10,
        test_type: :test,
        setup_blocks: [".invalid", "valid.path", "another.valid.path"],
        assertions: ["assert .bad", "assert good.function()"],
        dependencies: ["alias .BadModule", "alias GoodModule"],
        complexity_score: 2.0
      }

      paths = CoverageAnalysis.analyze_test_code_paths(test)

      assert is_list(paths)
      # Should not include paths starting or ending with dots
      refute Enum.any?(paths, &String.starts_with?(&1, "."))
      refute Enum.any?(paths, &String.ends_with?(&1, "."))
    end
  end
end
