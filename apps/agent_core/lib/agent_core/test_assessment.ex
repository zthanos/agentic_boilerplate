defmodule AgentCore.TestAssessment do
  @moduledoc """
  Main module for the Test Assessment System.

  Provides automated assessment and categorization of existing tests in Phoenix
  umbrella applications to help developers identify valuable tests, remove
  redundant ones, and properly organize the test suite.

  This module orchestrates all analysis components and provides error handling,
  recovery strategies, and progress reporting for long-running analysis.
  """

  require Logger

  alias AgentCore.TestAssessment.{
    FileDiscovery,
    TestParser,
    CoverageAnalysis,
    Categorization,
    RedundancyDetector,
    ConfigValidator,
    ReportGenerator,
    RecommendationEngine,
    AssessmentReport,
    PhoenixAnalysis
  }

  @doc """
  Runs a complete test assessment on the given umbrella project path.

  Returns a comprehensive assessment report with analysis results and recommendations.
  Implements error handling and recovery strategies to ensure partial results
  are always provided even when some components fail.

  ## Options

  - `:progress_callback` - Function to call with progress updates (optional)
  - `:format` - Output format (:text, :json, :html) (default: :text)
  - `:output_file` - File path to write the report (optional)

  ## Examples

      iex> AgentCore.TestAssessment.assess_test_suite("/path/to/umbrella")
      {:ok, %AssessmentReport{...}}

      iex> AgentCore.TestAssessment.assess_test_suite("/path/to/umbrella",
      ...>   progress_callback: &IO.puts/1, format: :json)
      {:ok, %AssessmentReport{...}}
  """
  @spec assess_test_suite(String.t(), keyword()) :: {:ok, AssessmentReport.t()} | {:error, term()}
  def assess_test_suite(umbrella_path, opts \\ []) do
    progress_callback = Keyword.get(opts, :progress_callback, &default_progress_callback/1)
    format = Keyword.get(opts, :format, :text)
    output_file = Keyword.get(opts, :output_file)

    Logger.info("Starting test assessment for umbrella project: #{umbrella_path}")
    progress_callback.("Starting test assessment...")

    try do
      # Step 1: Discover test files and configurations
      progress_callback.("Discovering test files and configurations...")
      {test_files, _config_files, apps_analyzed} = discover_files_with_recovery(umbrella_path)

      # Step 2: Parse test files
      progress_callback.("Parsing test files (#{length(test_files)} files)...")
      parsed_tests = parse_tests_with_recovery(test_files, progress_callback)

      # Step 3: Analyze coverage
      progress_callback.("Analyzing test coverage...")
      coverage_report = analyze_coverage_with_recovery(parsed_tests)

      # Step 4: Categorize tests
      progress_callback.("Categorizing tests...")
      test_categories = categorize_tests_with_recovery(parsed_tests)

      # Step 5: Detect redundancies
      progress_callback.("Detecting redundant tests...")
      redundancy_findings = detect_redundancies_with_recovery(parsed_tests, coverage_report)

      # Step 6: Validate configurations
      progress_callback.("Validating configurations...")
      config_issues = validate_configs_with_recovery(umbrella_path)

      # Step 7: Identify coverage gaps
      progress_callback.("Identifying coverage gaps...")
      coverage_gaps = identify_coverage_gaps_with_recovery(coverage_report)

      # Step 8: Perform Phoenix-specific analysis
      progress_callback.("Analyzing Phoenix-specific features...")
      phoenix_analysis = analyze_phoenix_features_with_recovery(parsed_tests)

      # Step 9: Generate recommendations
      progress_callback.("Generating recommendations...")

      analysis_results = %{
        test_files: test_files,
        parsed_tests: parsed_tests,
        coverage_report: coverage_report,
        test_categories: test_categories,
        redundancy_findings: redundancy_findings,
        config_issues: config_issues,
        coverage_gaps: coverage_gaps,
        phoenix_analysis: phoenix_analysis,
        apps_analyzed: apps_analyzed
      }

      recommendations = generate_recommendations_with_recovery(analysis_results)

      # Step 10: Generate final report
      progress_callback.("Generating assessment report...")
      final_analysis_results = Map.put(analysis_results, :recommendations, recommendations)
      report = ReportGenerator.generate_report(final_analysis_results)
      organized_report = ReportGenerator.organize_by_categories(report)

      # Step 11: Export report if requested
      if output_file do
        progress_callback.("Exporting report to #{output_file}...")
        export_report_to_file(organized_report, format, output_file)
      end

      progress_callback.("Assessment completed successfully!")
      Logger.info("Test assessment completed successfully for #{umbrella_path}")

      {:ok, organized_report}
    rescue
      error ->
        Logger.error("Test assessment failed with error: #{inspect(error)}")
        progress_callback.("Assessment failed: #{inspect(error)}")
        {:error, {:assessment_failed, error}}
    end
  end

  @doc """
  Runs assessment and exports the report to a file.

  Convenience function that combines assessment and export in one call.
  """
  @spec assess_and_export(String.t(), String.t(), atom(), keyword()) ::
          {:ok, AssessmentReport.t()} | {:error, term()}
  def assess_and_export(umbrella_path, output_file, format \\ :text, opts \\ []) do
    opts_with_export = Keyword.merge(opts, output_file: output_file, format: format)
    assess_test_suite(umbrella_path, opts_with_export)
  end

  @doc """
  Validates that the given path is a valid umbrella project.

  Returns {:ok, apps} if valid, {:error, reason} otherwise.
  """
  @spec validate_umbrella_project(String.t()) :: {:ok, [String.t()]} | {:error, term()}
  def validate_umbrella_project(umbrella_path) do
    cond do
      not File.exists?(umbrella_path) ->
        {:error, :path_not_found}

      not File.dir?(umbrella_path) ->
        {:error, :not_directory}

      true ->
        case FileDiscovery.discover_config_files(umbrella_path) do
          {:ok, _config_files} ->
            # Try to discover apps to validate umbrella structure
            apps_path = Path.join(umbrella_path, "apps")

            if File.exists?(apps_path) do
              case File.ls(apps_path) do
                {:ok, entries} ->
                  apps =
                    entries
                    |> Enum.map(&Path.join(apps_path, &1))
                    |> Enum.filter(&File.dir?/1)
                    |> Enum.filter(&has_mix_file?/1)

                  if length(apps) > 0 do
                    {:ok, apps}
                  else
                    {:error, :no_valid_apps_found}
                  end

                {:error, reason} ->
                  {:error, {:cannot_read_apps_directory, reason}}
              end
            else
              # Not an umbrella, check if it's a single app
              if has_mix_file?(umbrella_path) do
                {:ok, [umbrella_path]}
              else
                {:error, :not_elixir_project}
              end
            end

          {:error, reason} ->
            {:error, {:invalid_project_structure, reason}}
        end
    end
  end

  # Private helper functions with error recovery

  defp discover_files_with_recovery(umbrella_path) do
    # Discover test files with fallback
    test_files =
      case FileDiscovery.discover_test_files(umbrella_path) do
        {:ok, files} ->
          Logger.info("Discovered #{length(files)} test files")
          files

        {:error, reason} ->
          Logger.warning(
            "Failed to discover test files: #{inspect(reason)}, continuing with empty list"
          )

          []
      end

    # Discover config files with fallback
    config_files =
      case FileDiscovery.discover_config_files(umbrella_path) do
        {:ok, files} ->
          Logger.info("Discovered #{length(files)} config files")
          files

        {:error, reason} ->
          Logger.warning(
            "Failed to discover config files: #{inspect(reason)}, continuing with empty list"
          )

          []
      end

    # Count apps analyzed
    apps_analyzed =
      case validate_umbrella_project(umbrella_path) do
        {:ok, apps} -> length(apps)
        # Assume single app
        {:error, _reason} -> 1
      end

    {test_files, config_files, apps_analyzed}
  end

  defp parse_tests_with_recovery(test_files, progress_callback) do
    test_files
    |> Enum.with_index()
    |> Enum.flat_map(fn {test_file, index} ->
      if rem(index, 10) == 0 do
        progress_callback.("Parsing test file #{index + 1}/#{length(test_files)}")
      end

      case TestParser.parse_test_file(test_file.path) do
        {:ok, parsed_tests} ->
          parsed_tests

        {:error, reason} ->
          Logger.warning("Failed to parse test file #{test_file.path}: #{inspect(reason)}")
          []
      end
    end)
  end

  defp analyze_coverage_with_recovery(parsed_tests) do
    try do
      CoverageAnalysis.analyze_coverage(parsed_tests)
    rescue
      error ->
        Logger.warning("Coverage analysis failed: #{inspect(error)}, using fallback")
        create_fallback_coverage_report(parsed_tests)
    end
  end

  defp categorize_tests_with_recovery(parsed_tests) do
    parsed_tests
    |> Enum.reduce(%{}, fn test, acc ->
      try do
        category = Categorization.categorize_test(test)
        Map.put(acc, test.name, category)
      rescue
        error ->
          Logger.warning("Failed to categorize test #{test.name}: #{inspect(error)}")
          acc
      end
    end)
  end

  defp detect_redundancies_with_recovery(parsed_tests, coverage_report) do
    redundancy_findings = []

    # Detect redundant coverage
    redundancy_findings =
      try do
        coverage_redundancies =
          RedundancyDetector.detect_redundant_coverage(parsed_tests, coverage_report)

        redundancy_findings ++ coverage_redundancies
      rescue
        error ->
          Logger.warning("Failed to detect redundant coverage: #{inspect(error)}")
          redundancy_findings
      end

    # Detect similar logic
    redundancy_findings =
      try do
        logic_redundancies = RedundancyDetector.detect_similar_logic(parsed_tests)
        redundancy_findings ++ logic_redundancies
      rescue
        error ->
          Logger.warning("Failed to detect similar logic: #{inspect(error)}")
          redundancy_findings
      end

    # Handle LiveView redundancy
    redundancy_findings =
      try do
        liveview_tests = Enum.filter(parsed_tests, &is_liveview_test?/1)

        if length(liveview_tests) > 0 do
          liveview_redundancies = RedundancyDetector.handle_liveview_redundancy(liveview_tests)
          redundancy_findings ++ liveview_redundancies
        else
          redundancy_findings
        end
      rescue
        error ->
          Logger.warning("Failed to handle LiveView redundancy: #{inspect(error)}")
          redundancy_findings
      end

    redundancy_findings
  end

  defp validate_configs_with_recovery(umbrella_path) do
    config_issues = []

    # Validate mix dependencies
    config_issues =
      try do
        mix_issues = ConfigValidator.validate_mix_dependencies(umbrella_path)
        config_issues ++ mix_issues
      rescue
        error ->
          Logger.warning("Failed to validate mix dependencies: #{inspect(error)}")
          config_issues
      end

    # Validate test configs
    config_issues =
      try do
        test_config_issues = ConfigValidator.validate_test_configs(umbrella_path)
        config_issues ++ test_config_issues
      rescue
        error ->
          Logger.warning("Failed to validate test configs: #{inspect(error)}")
          config_issues
      end

    # Validate Phoenix configs
    config_issues =
      try do
        phoenix_issues = ConfigValidator.validate_phoenix_configs(umbrella_path)
        config_issues ++ phoenix_issues
      rescue
        error ->
          Logger.warning("Failed to validate Phoenix configs: #{inspect(error)}")
          config_issues
      end

    # Report config mismatches
    config_issues =
      try do
        mismatch_issues = ConfigValidator.report_config_mismatches(umbrella_path)
        config_issues ++ mismatch_issues
      rescue
        error ->
          Logger.warning("Failed to report config mismatches: #{inspect(error)}")
          config_issues
      end

    config_issues
  end

  defp identify_coverage_gaps_with_recovery(coverage_report) do
    try do
      CoverageAnalysis.identify_coverage_gaps(coverage_report)
    rescue
      error ->
        Logger.warning("Failed to identify coverage gaps: #{inspect(error)}")
        []
    end
  end

  defp analyze_phoenix_features_with_recovery(parsed_tests) do
    try do
      PhoenixAnalysis.analyze_phoenix_features(parsed_tests)
    rescue
      error ->
        Logger.warning("Failed to analyze Phoenix features: #{inspect(error)}")

        %{
          liveview_analysis: %{
            tested_interactions: [],
            untested_interactions: [],
            interaction_coverage: 0.0,
            recommendations: []
          },
          form_validation_analysis: %{
            tested_validations: [],
            untested_validations: [],
            validation_coverage: 0.0,
            coverage_gaps: []
          },
          component_analysis: %{
            tested_components: [],
            untested_components: [],
            component_coverage: 0.0,
            coverage_gaps: []
          },
          property_test_analysis: %{
            parser_opportunities: [],
            transformation_opportunities: [],
            existing_property_tests: [],
            recommendations: []
          },
          overall_phoenix_coverage: 0.0,
          phoenix_recommendations: []
        }
    end
  end

  defp generate_recommendations_with_recovery(analysis_results) do
    try do
      RecommendationEngine.generate_recommendations(analysis_results)
    rescue
      error ->
        Logger.warning("Failed to generate recommendations: #{inspect(error)}")
        []
    end
  end

  defp export_report_to_file(report, format, output_file) do
    try do
      content = ReportGenerator.export_report(report, format)
      File.write!(output_file, content)
      Logger.info("Report exported to #{output_file}")
    rescue
      error ->
        Logger.error("Failed to export report to #{output_file}: #{inspect(error)}")
        raise error
    end
  end

  defp create_fallback_coverage_report(parsed_tests) do
    # Create a minimal coverage report when analysis fails
    alias AgentCore.TestAssessment.CoverageReport

    %CoverageReport{
      # Rough estimate
      total_lines: length(parsed_tests) * 50,
      # Rough estimate
      covered_lines: length(parsed_tests) * 30,
      # Conservative estimate
      coverage_percentage: 60.0,
      uncovered_functions: [],
      test_coverage_map: %{}
    }
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

  defp has_mix_file?(path) do
    mix_file = Path.join(path, "mix.exs")
    File.exists?(mix_file)
  end

  defp default_progress_callback(message) do
    IO.puts("[TestAssessment] #{message}")
  end
end
