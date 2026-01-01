defmodule Mix.Tasks.TestAssessment do
  @moduledoc """
  Mix task for running test assessment on Phoenix umbrella projects.

  This task provides a command-line interface for the Test Assessment System,
  allowing developers to analyze their test suites and generate comprehensive
  reports with recommendations for improvement.

  ## Usage

      mix test_assessment [path] [options]

  ## Arguments

  - `path` - Path to the umbrella project (defaults to current directory)

  ## Options

  - `--format` - Output format: text, json, or html (default: text)
  - `--output` - Output file path (optional, prints to stdout if not specified)
  - `--verbose` - Enable verbose progress reporting
  - `--validate-only` - Only validate project structure without running full assessment

  ## Examples

      # Run assessment on current directory
      mix test_assessment

      # Run assessment on specific path with JSON output
      mix test_assessment /path/to/project --format json --output report.json

      # Run assessment with verbose progress
      mix test_assessment --verbose

      # Validate project structure only
      mix test_assessment --validate-only
  """

  use Mix.Task

  alias AgentCore.TestAssessment

  @shortdoc "Runs test assessment on Phoenix umbrella projects"

  @switches [
    format: :string,
    output: :string,
    verbose: :boolean,
    validate_only: :boolean,
    help: :boolean
  ]

  @aliases [
    f: :format,
    o: :output,
    v: :verbose,
    h: :help
  ]

  @impl Mix.Task
  def run(args) do
    # Start the application to ensure all dependencies are loaded
    Mix.Task.run("app.start")

    {opts, args, _invalid} = OptionParser.parse(args, switches: @switches, aliases: @aliases)

    if opts[:help] do
      print_help()
    else
      # Get project path (default to current directory)
      project_path =
        case args do
          [path | _] -> Path.expand(path)
          [] -> File.cwd!()
        end

      # Validate options
      format = validate_format(opts[:format] || "text")
      output_file = opts[:output]
      verbose = opts[:verbose] || false
      validate_only = opts[:validate_only] || false

      # Set up progress callback
      progress_callback =
        if verbose do
          &verbose_progress_callback/1
        else
          &simple_progress_callback/1
        end

      Mix.shell().info("Test Assessment System")
      Mix.shell().info("Project: #{project_path}")
      Mix.shell().info("Format: #{format}")
      if output_file, do: Mix.shell().info("Output: #{output_file}")
      Mix.shell().info("")

      if validate_only do
        run_validation_only(project_path)
      else
        run_full_assessment(project_path, format, output_file, progress_callback)
      end
    end
  end

  defp run_validation_only(project_path) do
    Mix.shell().info("Validating project structure...")

    case TestAssessment.validate_umbrella_project(project_path) do
      {:ok, apps} ->
        Mix.shell().info("✓ Valid project structure detected")
        Mix.shell().info("  Apps found: #{length(apps)}")

        apps
        |> Enum.with_index(1)
        |> Enum.each(fn {app_path, index} ->
          app_name = Path.basename(app_path)
          Mix.shell().info("  #{index}. #{app_name} (#{app_path})")
        end)

        Mix.shell().info("")
        Mix.shell().info("Project is ready for test assessment.")

      {:error, reason} ->
        Mix.shell().error("✗ Invalid project structure: #{format_error(reason)}")
        Mix.shell().error("")

        Mix.shell().error(
          "Please ensure you're running this command from a valid Elixir/Phoenix project."
        )

        System.halt(1)
    end
  end

  defp run_full_assessment(project_path, format, output_file, progress_callback) do
    # First validate the project
    case TestAssessment.validate_umbrella_project(project_path) do
      {:ok, apps} ->
        Mix.shell().info("✓ Project structure validated (#{length(apps)} apps)")

      {:error, reason} ->
        Mix.shell().error("✗ Invalid project structure: #{format_error(reason)}")
        System.halt(1)
    end

    # Run the assessment
    opts = [
      progress_callback: progress_callback,
      format: format,
      output_file: output_file
    ]

    case TestAssessment.assess_test_suite(project_path, opts) do
      {:ok, report} ->
        Mix.shell().info("")
        Mix.shell().info("✓ Assessment completed successfully!")
        print_summary(report)

        unless output_file do
          Mix.shell().info("")
          Mix.shell().info("Full Report:")
          Mix.shell().info("=" |> String.duplicate(50))

          report_content = AgentCore.TestAssessment.ReportGenerator.export_report(report, format)
          Mix.shell().info(report_content)
        end

      {:error, reason} ->
        Mix.shell().error("✗ Assessment failed: #{format_error(reason)}")
        System.halt(1)
    end
  end

  defp validate_format(format_str) do
    case String.downcase(format_str) do
      "text" ->
        :text

      "json" ->
        :json

      "html" ->
        :html

      invalid ->
        Mix.shell().error("Invalid format: #{invalid}. Valid formats: text, json, html")
        System.halt(1)
    end
  end

  defp verbose_progress_callback(message) do
    timestamp = DateTime.utc_now() |> DateTime.to_time() |> Time.to_string()
    Mix.shell().info("[#{timestamp}] #{message}")
  end

  defp simple_progress_callback(message) do
    Mix.shell().info("#{message}")
  end

  defp print_summary(report) do
    summary = report.summary

    Mix.shell().info("")
    Mix.shell().info("Assessment Summary:")
    Mix.shell().info("  Tests Analyzed: #{summary.total_tests}")
    Mix.shell().info("  Test Files: #{summary.total_test_files}")
    Mix.shell().info("  Apps: #{summary.apps_analyzed}")
    Mix.shell().info("  Overall Score: #{Float.round(summary.overall_score, 1)}/100")
    Mix.shell().info("")
    Mix.shell().info("Issues Found:")
    Mix.shell().info("  Redundant Tests: #{summary.redundant_tests_found}")
    Mix.shell().info("  Coverage Gaps: #{summary.coverage_gaps_found}")
    Mix.shell().info("  Config Issues: #{summary.config_issues_found}")
    Mix.shell().info("  Recommendations: #{length(report.recommendations)}")
  end

  defp format_error(reason) do
    case reason do
      :path_not_found -> "Path does not exist"
      :not_directory -> "Path is not a directory"
      :no_valid_apps_found -> "No valid Elixir apps found in umbrella structure"
      :not_elixir_project -> "Not a valid Elixir project (no mix.exs found)"
      {:cannot_read_apps_directory, reason} -> "Cannot read apps directory: #{inspect(reason)}"
      {:invalid_project_structure, reason} -> "Invalid project structure: #{inspect(reason)}"
      {:assessment_failed, error} -> "Assessment failed: #{inspect(error)}"
      other -> inspect(other)
    end
  end

  defp print_help do
    Mix.shell().info(@moduledoc)
  end
end
