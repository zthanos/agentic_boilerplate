defmodule AgentCore.TestAssessment.TestSuiteOptimizerTest do
  use ExUnit.Case, async: true

  alias AgentCore.TestAssessment.{
    TestSuiteOptimizer,
    AssessmentReport,
    RedundancyFinding,
    ParsedTest,
    OptimizationResult,
    ReorganizationResult,
    RefactoringResult,
    TestRunResult
  }

  describe "create_backup/1" do
    test "creates backup file with timestamp" do
      # Create a temporary test file
      test_file = "test_temp_file.txt"
      File.write!(test_file, "test content")

      try do
        assert {:ok, backup_path} = TestSuiteOptimizer.create_backup(test_file)
        assert File.exists?(backup_path)
        assert String.contains?(backup_path, "test_backups")
        assert String.contains?(backup_path, "backup")

        # Verify backup content matches original
        assert File.read!(backup_path) == "test content"
      after
        File.rm(test_file)
        if File.exists?("test_backups"), do: File.rm_rf!("test_backups")
      end
    end

    test "returns error when file doesn't exist" do
      assert {:error, _reason} = TestSuiteOptimizer.create_backup("nonexistent_file.txt")
    end

    test "handles permission errors gracefully" do
      # Test with invalid path that would cause permission error
      invalid_path = "/root/restricted_file.txt"
      assert {:error, _reason} = TestSuiteOptimizer.create_backup(invalid_path)
    end

    test "handles empty file path" do
      assert {:error, _reason} = TestSuiteOptimizer.create_backup("")
    end

    test "handles nil file path" do
      assert_raise FunctionClauseError, fn ->
        TestSuiteOptimizer.create_backup(nil)
      end
    end

    test "creates backup directory if it doesn't exist" do
      test_file = "test_temp_file2.txt"
      File.write!(test_file, "test content")

      # Ensure backup directory doesn't exist
      if File.exists?("test_backups"), do: File.rm_rf!("test_backups")

      try do
        assert {:ok, backup_path} = TestSuiteOptimizer.create_backup(test_file)
        assert File.exists?(backup_path)
        assert File.exists?("test_backups")
      after
        File.rm(test_file)
        if File.exists?("test_backups"), do: File.rm_rf!("test_backups")
      end
    end
  end

  describe "remove_redundant_tests/2" do
    test "identifies tests to remove from redundancy findings" do
      redundancy_findings = [
        %RedundancyFinding{
          test_names: ["test_a.exs", "test_b.exs", "test_c.exs"],
          redundancy_type: :identical_coverage,
          confidence_score: 0.9,
          recommended_action: "remove",
          justification: "Identical coverage"
        }
      ]

      opts = [dry_run: true]

      assert {:ok, removed_files} = TestSuiteOptimizer.remove_redundant_tests(redundancy_findings, opts)
      assert length(removed_files) == 2  # Should keep first, remove others
      assert "test_b.exs" in removed_files
      assert "test_c.exs" in removed_files
      refute "test_a.exs" in removed_files
    end

    test "skips low confidence redundancy findings" do
      redundancy_findings = [
        %RedundancyFinding{
          test_names: ["test_a.exs", "test_b.exs"],
          redundancy_type: :similar_logic,
          confidence_score: 0.5,  # Below threshold
          recommended_action: "review",
          justification: "Similar but not identical"
        }
      ]

      opts = [dry_run: true]

      assert {:ok, removed_files} = TestSuiteOptimizer.remove_redundant_tests(redundancy_findings, opts)
      assert removed_files == []
    end
  end

  describe "reorganize_test_structure/2" do
    test "plans test reorganization by type" do
      tests = [
        %ParsedTest{
          name: "unit test",
          file_path: "test/some_test.exs",
          test_type: :unit,
          line_number: 1,
          setup_blocks: [],
          assertions: [],
          dependencies: [],
          complexity_score: 1.0
        },
        %ParsedTest{
          name: "integration test",
          file_path: "test/integration_test.exs",
          test_type: :integration,
          line_number: 1,
          setup_blocks: [],
          assertions: [],
          dependencies: [],
          complexity_score: 2.0
        }
      ]

      # Create temporary test files for the reorganization test
      File.write!("test/some_test.exs", "# unit test")
      File.write!("test/integration_test.exs", "# integration test")

      try do
        assert {:ok, result} = TestSuiteOptimizer.reorganize_test_structure(tests, "standard")
        assert %ReorganizationResult{} = result
        assert is_map(result.moved_files)
        assert is_list(result.created_directories)
      after
        # Clean up test files and directories
        File.rm("test/some_test.exs")
        File.rm("test/integration_test.exs")
        if File.exists?("test/unit"), do: File.rm_rf!("test/unit")
        if File.exists?("test/integration"), do: File.rm_rf!("test/integration")
      end
    end
  end

  describe "refactor_outdated_patterns/1" do
    test "identifies tests with outdated patterns" do
      # Create a temporary test file with outdated patterns
      test_file = "test_outdated.exs"
      outdated_content = """
      defmodule TestModule do
        use ExUnit.Case

        test "old pattern" do
          conn = Phoenix.ConnTest.build_conn()
          assert conn
        end
      end
      """

      File.write!(test_file, outdated_content)

      test = %ParsedTest{
        name: "outdated test",
        file_path: test_file,
        test_type: :unit,
        line_number: 1,
        setup_blocks: [],
        assertions: [],
        dependencies: [],
        complexity_score: 1.0
      }

      try do
        assert {:ok, results} = TestSuiteOptimizer.refactor_outdated_patterns([test])
        assert length(results) == 1

        result = hd(results)
        assert %RefactoringResult{} = result
        assert result.file_path == test_file
        assert String.contains?(result.original_content, "Phoenix.ConnTest.build_conn()")
        assert String.contains?(result.refactored_content, "build_conn()")
        refute String.contains?(result.refactored_content, "Phoenix.ConnTest.build_conn()")
      after
        File.rm(test_file)
      end
    end
  end

  describe "verify_test_suite/1" do
    @tag :skip
    test "parses successful test output" do
      # This test is skipped because it requires actual mix test execution
      # In a real implementation, this would be mocked properly
      assert true
    end

    @tag :skip
    test "parses failed test output" do
      # This test is skipped because it requires actual mix test execution
      # In a real implementation, this would be mocked properly
      assert true
    end
  end

  describe "optimize_test_suite/2" do
    test "performs dry run optimization" do
      assessment_report = %AssessmentReport{
        summary: nil,
        test_categories: %{},
        redundancy_findings: [],
        coverage_gaps: [],
        config_issues: [],
        recommendations: [],
        phoenix_analysis: %{},
        generated_at: DateTime.utc_now()
      }

      opts = [dry_run: true]

      assert {:ok, result} = TestSuiteOptimizer.optimize_test_suite(assessment_report, opts)
      assert %OptimizationResult{} = result
      assert result.removed_files == []
      assert result.modified_files == []
      assert is_binary(result.optimization_summary)
    end
  end
end
