defmodule AgentCore.TestAssessment.TestSuiteOptimizer do
  @moduledoc """
  Provides automated test suite optimization capabilities including redundant test removal,
  test file reorganization, pattern refactoring, backup creation, and post-optimization verification.
  """

  alias AgentCore.TestAssessment.{
    AssessmentReport,
    RedundancyFinding,
    ParsedTest,
    OptimizationResult,
    ReorganizationResult,
    RefactoringResult,
    TestRunResult
  }

  require Logger

  @doc """
  Optimizes a test suite based on assessment report findings.

  ## Options
  - `:backup_dir` - Directory to store backups (default: "test_backups")
  - `:dry_run` - If true, only shows what would be done without making changes
  - `:remove_redundant` - Whether to remove redundant tests (default: true)
  - `:reorganize` - Whether to reorganize test structure (default: true)
  - `:refactor_patterns` - Whether to refactor outdated patterns (default: true)
  """
  @spec optimize_test_suite(AssessmentReport.t(), keyword()) ::
          {:ok, OptimizationResult.t()} | {:error, term()}
  def optimize_test_suite(assessment_report, opts \\ []) do
    opts =
      Keyword.merge(
        [
          backup_dir: "test_backups",
          dry_run: false,
          remove_redundant: true,
          reorganize: true,
          refactor_patterns: true
        ],
        opts
      )

    with {:ok, backup_dir} <- ensure_backup_directory(opts[:backup_dir]),
         {:ok, removed_files} <-
           maybe_remove_redundant_tests(assessment_report.redundancy_findings, opts),
         {:ok, reorganization_result} <- maybe_reorganize_tests(assessment_report, opts),
         {:ok, refactoring_results} <- maybe_refactor_patterns(assessment_report, opts),
         {:ok, test_run_result} <- verify_test_suite_if_not_dry_run(opts) do
      optimization_result = %OptimizationResult{
        removed_files: removed_files,
        modified_files: get_modified_files(reorganization_result, refactoring_results),
        reorganized_files: reorganization_result.moved_files,
        backup_directory: backup_dir,
        test_run_result: test_run_result,
        optimization_summary:
          generate_optimization_summary(removed_files, reorganization_result, refactoring_results)
      }

      {:ok, optimization_result}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Removes redundant tests with safety checks, keeping the highest quality version.
  """
  @spec remove_redundant_tests([RedundancyFinding.t()], keyword()) ::
          {:ok, [String.t()]} | {:error, term()}
  def remove_redundant_tests(redundancy_findings, opts \\ []) do
    dry_run = Keyword.get(opts, :dry_run, false)
    backup_dir = Keyword.get(opts, :backup_dir, "test_backups")

    removed_files =
      redundancy_findings
      |> Enum.filter(&should_remove_redundant_test?/1)
      |> Enum.flat_map(&identify_tests_to_remove/1)
      |> Enum.uniq()

    if dry_run do
      Logger.info("DRY RUN: Would remove #{length(removed_files)} redundant test files")
      {:ok, removed_files}
    else
      case remove_test_files_safely(removed_files, backup_dir) do
        {:ok, _} -> {:ok, removed_files}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Reorganizes test files into appropriate directory structures with optimized naming.
  """
  @spec reorganize_test_structure([ParsedTest.t()], String.t()) ::
          {:ok, ReorganizationResult.t()} | {:error, term()}
  def reorganize_test_structure(tests, target_structure) do
    reorganization_plan = plan_test_reorganization(tests, target_structure)

    with {:ok, moved_files} <- execute_file_moves(reorganization_plan.moves),
         {:ok, created_dirs} <- create_target_directories(reorganization_plan.new_directories),
         {:ok, updated_imports} <- update_import_statements(reorganization_plan.import_updates) do
      result = %ReorganizationResult{
        moved_files: moved_files,
        created_directories: created_dirs,
        updated_imports: updated_imports,
        conflicts: reorganization_plan.conflicts
      }

      {:ok, result}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Refactors tests using outdated Phoenix patterns to modern practices.
  """
  @spec refactor_outdated_patterns([ParsedTest.t()]) ::
          {:ok, [RefactoringResult.t()]} | {:error, term()}
  def refactor_outdated_patterns(tests) do
    tests
    |> Enum.filter(&has_outdated_patterns?/1)
    |> Enum.map(&refactor_test_file/1)
    |> collect_results()
  end

  @doc """
  Creates a backup of a file or directory before modification.
  """
  @spec create_backup(String.t()) :: {:ok, String.t()} | {:error, term()}
  def create_backup(file_path) do
    backup_dir = "test_backups"
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    backup_filename = "#{Path.basename(file_path)}.backup.#{timestamp}"
    backup_path = Path.join(backup_dir, backup_filename)

    with :ok <- File.mkdir_p(backup_dir),
         {:ok, _} <- File.copy(file_path, backup_path) do
      Logger.info("Created backup: #{backup_path}")
      {:ok, backup_path}
    else
      {:error, reason} ->
        Logger.error("Failed to create backup for #{file_path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Verifies the test suite by running all tests after optimization.
  """
  @spec verify_test_suite(String.t()) :: {:ok, TestRunResult.t()} | {:error, term()}
  def verify_test_suite(project_path) do
    start_time = System.monotonic_time(:millisecond)

    case System.cmd("mix", ["test"], cd: project_path, stderr_to_stdout: true) do
      {output, 0} ->
        end_time = System.monotonic_time(:millisecond)
        execution_time = (end_time - start_time) / 1000.0

        test_stats = parse_test_output(output)

        result = %TestRunResult{
          success: true,
          total_tests: test_stats.total,
          passed_tests: test_stats.passed,
          failed_tests: test_stats.failed,
          execution_time: execution_time,
          failure_details: []
        }

        {:ok, result}

      {output, exit_code} ->
        end_time = System.monotonic_time(:millisecond)
        execution_time = (end_time - start_time) / 1000.0

        test_stats = parse_test_output(output)
        failure_details = extract_failure_details(output)

        result = %TestRunResult{
          success: false,
          total_tests: test_stats.total,
          passed_tests: test_stats.passed,
          failed_tests: test_stats.failed,
          execution_time: execution_time,
          failure_details: failure_details
        }

        Logger.error("Test suite verification failed with exit code #{exit_code}")
        # Return success with failure details for analysis
        {:ok, result}
    end
  end

  # Private helper functions

  defp ensure_backup_directory(backup_dir) do
    case File.mkdir_p(backup_dir) do
      :ok -> {:ok, backup_dir}
      {:error, reason} -> {:error, "Failed to create backup directory: #{inspect(reason)}"}
    end
  end

  defp maybe_remove_redundant_tests(redundancy_findings, opts) do
    if Keyword.get(opts, :remove_redundant, true) do
      remove_redundant_tests(redundancy_findings, opts)
    else
      {:ok, []}
    end
  end

  defp maybe_reorganize_tests(assessment_report, opts) do
    if Keyword.get(opts, :reorganize, true) do
      # Extract tests from assessment report (simplified for now)
      tests = extract_tests_from_report(assessment_report)
      reorganize_test_structure(tests, "standard")
    else
      {:ok,
       %ReorganizationResult{
         moved_files: %{},
         created_directories: [],
         updated_imports: [],
         conflicts: []
       }}
    end
  end

  defp maybe_refactor_patterns(assessment_report, opts) do
    if Keyword.get(opts, :refactor_patterns, true) do
      tests = extract_tests_from_report(assessment_report)
      refactor_outdated_patterns(tests)
    else
      {:ok, []}
    end
  end

  defp verify_test_suite_if_not_dry_run(opts) do
    if Keyword.get(opts, :dry_run, false) do
      {:ok,
       %TestRunResult{
         success: true,
         total_tests: 0,
         passed_tests: 0,
         failed_tests: 0,
         execution_time: 0.0,
         failure_details: []
       }}
    else
      verify_test_suite(".")
    end
  end

  defp should_remove_redundant_test?(redundancy_finding) do
    redundancy_finding.confidence_score >= 0.8 and
      redundancy_finding.redundancy_type in [:identical_coverage, :duplicate_assertions]
  end

  defp identify_tests_to_remove(redundancy_finding) do
    # Keep the first test (assumed to be highest quality) and remove others
    case redundancy_finding.test_names do
      [_keep | remove] -> remove
      [] -> []
    end
  end

  defp remove_test_files_safely(file_paths, backup_dir) do
    results =
      Enum.map(file_paths, fn file_path ->
        with {:ok, _backup_path} <- create_backup(file_path),
             :ok <- File.rm(file_path) do
          Logger.info("Removed redundant test file: #{file_path}")
          {:ok, file_path}
        else
          {:error, reason} ->
            Logger.error("Failed to remove #{file_path}: #{inspect(reason)}")
            {:error, {file_path, reason}}
        end
      end)

    case Enum.split_with(results, &match?({:ok, _}, &1)) do
      {successes, []} ->
        removed_files = Enum.map(successes, fn {:ok, path} -> path end)
        {:ok, removed_files}

      {_successes, errors} ->
        {:error, {:partial_failure, errors}}
    end
  end

  defp plan_test_reorganization(tests, target_structure) do
    # Simplified reorganization planning
    moves =
      tests
      |> Enum.map(&plan_test_move(&1, target_structure))
      |> Enum.reject(&is_nil/1)
      |> Map.new()

    new_directories =
      moves
      |> Map.values()
      |> Enum.map(&Path.dirname/1)
      |> Enum.uniq()

    %{
      moves: moves,
      new_directories: new_directories,
      import_updates: [],
      conflicts: []
    }
  end

  defp plan_test_move(test, _target_structure) do
    # Simple heuristic: organize by test type
    new_dir =
      case test.test_type do
        :unit -> "test/unit"
        :integration -> "test/integration"
        :property_based -> "test/property"
        _ -> "test/other"
      end

    new_path = Path.join(new_dir, Path.basename(test.file_path))

    if test.file_path != new_path do
      {test.file_path, new_path}
    else
      nil
    end
  end

  defp execute_file_moves(moves) do
    results =
      Enum.map(moves, fn {from, to} ->
        with :ok <- File.mkdir_p(Path.dirname(to)),
             {:ok, _} <- File.copy(from, to),
             :ok <- File.rm(from) do
          Logger.info("Moved #{from} -> #{to}")
          {:ok, {from, to}}
        else
          {:error, reason} ->
            Logger.error("Failed to move #{from} -> #{to}: #{inspect(reason)}")
            {:error, {from, to, reason}}
        end
      end)

    case Enum.split_with(results, &match?({:ok, _}, &1)) do
      {successes, []} ->
        moved_files = Enum.map(successes, fn {:ok, move} -> move end) |> Map.new()
        {:ok, moved_files}

      {_successes, errors} ->
        {:error, {:move_failures, errors}}
    end
  end

  defp create_target_directories(directories) do
    results =
      Enum.map(directories, fn dir ->
        case File.mkdir_p(dir) do
          :ok -> {:ok, dir}
          {:error, reason} -> {:error, {dir, reason}}
        end
      end)

    case Enum.split_with(results, &match?({:ok, _}, &1)) do
      {successes, []} ->
        created_dirs = Enum.map(successes, fn {:ok, dir} -> dir end)
        {:ok, created_dirs}

      {_successes, errors} ->
        {:error, {:directory_creation_failures, errors}}
    end
  end

  defp update_import_statements(_import_updates) do
    # Placeholder for import statement updates
    {:ok, []}
  end

  defp has_outdated_patterns?(test) do
    # Check for common outdated Phoenix test patterns
    file_content =
      case File.read(test.file_path) do
        {:ok, content} -> content
        {:error, _} -> ""
      end

    outdated_patterns = [
      ~r/Phoenix\.ConnTest\.build_conn/,
      ~r/Phoenix\.View\.render_to_string/,
      ~r/Phoenix\.HTML\.Form\.form_for/,
      ~r/Phoenix\.LiveViewTest\.live_isolated/
    ]

    Enum.any?(outdated_patterns, &Regex.match?(&1, file_content))
  end

  defp refactor_test_file(test) do
    case File.read(test.file_path) do
      {:ok, original_content} ->
        refactored_content = apply_refactoring_patterns(original_content)
        changes_applied = identify_changes(original_content, refactored_content)

        case File.write(test.file_path, refactored_content) do
          :ok ->
            Logger.info("Refactored outdated patterns in #{test.file_path}")

            {:ok,
             %RefactoringResult{
               file_path: test.file_path,
               original_content: original_content,
               refactored_content: refactored_content,
               changes_applied: changes_applied,
               warnings: []
             }}

          {:error, reason} ->
            {:error, {test.file_path, reason}}
        end

      {:error, reason} ->
        {:error, {test.file_path, reason}}
    end
  end

  defp apply_refactoring_patterns(content) do
    content
    |> String.replace(~r/Phoenix\.ConnTest\.build_conn\(\)/, "build_conn()")
    |> String.replace(~r/Phoenix\.View\.render_to_string/, "Phoenix.Template.render_to_string")
    |> String.replace(~r/Phoenix\.HTML\.Form\.form_for/, "Phoenix.Component.form")
    |> String.replace(~r/Phoenix\.LiveViewTest\.live_isolated/, "Phoenix.LiveViewTest.live")
  end

  defp identify_changes(original, refactored) do
    if original == refactored do
      []
    else
      ["Updated outdated Phoenix test patterns"]
    end
  end

  defp collect_results(results) do
    case Enum.split_with(results, &match?({:ok, _}, &1)) do
      {successes, []} ->
        refactoring_results = Enum.map(successes, fn {:ok, result} -> result end)
        {:ok, refactoring_results}

      {_successes, errors} ->
        {:error, {:refactoring_failures, errors}}
    end
  end

  defp get_modified_files(reorganization_result, refactoring_results) do
    moved_files = Map.keys(reorganization_result.moved_files)
    refactored_files = Enum.map(refactoring_results, & &1.file_path)

    (moved_files ++ refactored_files) |> Enum.uniq()
  end

  defp generate_optimization_summary(removed_files, reorganization_result, refactoring_results) do
    removed_count = length(removed_files)
    moved_count = map_size(reorganization_result.moved_files)
    refactored_count = length(refactoring_results)

    "Optimization completed: #{removed_count} files removed, #{moved_count} files reorganized, #{refactored_count} files refactored"
  end

  defp extract_tests_from_report(_assessment_report) do
    # Placeholder - in real implementation, this would extract ParsedTest structs
    # from the assessment report
    []
  end

  defp parse_test_output(output) do
    # Parse mix test output to extract test statistics
    total_regex = ~r/(\d+) tests?/
    failed_regex = ~r/(\d+) failures?/

    total =
      case Regex.run(total_regex, output) do
        [_, count] -> String.to_integer(count)
        nil -> 0
      end

    failed =
      case Regex.run(failed_regex, output) do
        [_, count] -> String.to_integer(count)
        nil -> 0
      end

    %{total: total, passed: total - failed, failed: failed}
  end

  defp extract_failure_details(output) do
    # Extract failure details from test output
    output
    |> String.split("\n")
    |> Enum.filter(&String.contains?(&1, "FAIL"))
    # Limit to first 10 failures
    |> Enum.take(10)
  end
end
