defmodule AgentCore.TestAssessmentTest do
  use ExUnit.Case, async: true

  alias AgentCore.TestAssessment

  alias AgentCore.TestAssessment.{
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
      assert category.confidence_scores[:unit] == 0.8
    end

    test "CoverageReport struct can be created" do
      report = %CoverageReport{
        total_lines: 100,
        covered_lines: 85,
        coverage_percentage: 85.0,
        uncovered_functions: ["MyModule.uncovered_function/1"],
        test_coverage_map: %{"test1" => ["MyModule.function1/1"]}
      }

      assert report.coverage_percentage == 85.0
      assert length(report.uncovered_functions) == 1
    end

    test "AssessmentReport struct can be created" do
      report = %AssessmentReport{
        summary: nil,
        test_categories: %{},
        redundancy_findings: [],
        coverage_gaps: [],
        config_issues: [],
        recommendations: [],
        generated_at: DateTime.utc_now()
      }

      assert is_struct(report, AssessmentReport)
      assert report.redundancy_findings == []
    end
  end

  describe "main assessment function" do
    test "assess_test_suite handles invalid path gracefully" do
      # Test with a non-existent path - should still return a report with config issues
      result = TestAssessment.assess_test_suite("/fake/path")

      assert {:ok, report} = result
      assert is_struct(report, AssessmentReport)
      assert report.summary.total_tests == 0
      assert report.summary.total_test_files == 0
      # Should have config issues for invalid path
      assert length(report.config_issues) > 0
    end

    test "validate_umbrella_project returns error for non-existent path" do
      assert {:error, :path_not_found} =
               TestAssessment.validate_umbrella_project("/non/existent/path")
    end

    test "validate_umbrella_project returns error for non-directory" do
      # Create a temporary file
      temp_file = System.tmp_dir!() |> Path.join("test_file.txt")
      File.write!(temp_file, "test content")

      assert {:error, :not_directory} = TestAssessment.validate_umbrella_project(temp_file)

      # Clean up
      File.rm!(temp_file)
    end

    test "validate_umbrella_project handles empty path" do
      assert {:error, :path_not_found} = TestAssessment.validate_umbrella_project("")
    end

    test "validate_umbrella_project handles nil path" do
      assert_raise FunctionClauseError, fn ->
        TestAssessment.validate_umbrella_project(nil)
      end
    end

    test "validate_umbrella_project handles directory without mix.exs" do
      # Create a temporary directory without mix.exs
      temp_dir = System.tmp_dir!() |> Path.join("empty_project")
      File.mkdir_p!(temp_dir)

      try do
        assert {:error, {:invalid_project_structure, :not_elixir_project}} =
                 TestAssessment.validate_umbrella_project(temp_dir)
      after
        File.rm_rf!(temp_dir)
      end
    end

    test "validate_umbrella_project handles umbrella without apps" do
      # Create a temporary directory with mix.exs but no apps
      temp_dir = System.tmp_dir!() |> Path.join("fake_umbrella")
      File.mkdir_p!(temp_dir)
      File.write!(Path.join(temp_dir, "mix.exs"), "defmodule Test.MixProject do\nend")

      try do
        # This will be treated as a single app project since it has mix.exs
        assert {:ok, [^temp_dir]} = TestAssessment.validate_umbrella_project(temp_dir)
      after
        File.rm_rf!(temp_dir)
      end
    end

    test "validate_umbrella_project handles permission errors" do
      # Test with a path that would cause permission issues (if it exists)
      restricted_path = "/root/restricted"
      result = TestAssessment.validate_umbrella_project(restricted_path)

      # Should return an error (either path_not_found or permission-related)
      assert {:error, _reason} = result
    end

    test "assess_test_suite with progress callback" do
      progress_messages = []

      progress_callback = fn message ->
        send(self(), {:progress, message})
      end

      # Run assessment with progress callback
      TestAssessment.assess_test_suite("/fake/path", progress_callback: progress_callback)

      # Collect progress messages
      messages = collect_progress_messages([])

      # Should have received progress messages
      assert length(messages) > 0
      assert Enum.any?(messages, &String.contains?(&1, "Starting test assessment"))
    end
  end

  # Helper function to collect progress messages
  defp collect_progress_messages(acc) do
    receive do
      {:progress, message} -> collect_progress_messages([message | acc])
    after
      100 -> Enum.reverse(acc)
    end
  end
end
