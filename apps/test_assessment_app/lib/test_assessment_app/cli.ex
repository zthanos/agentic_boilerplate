defmodule TestAssessmentApp.CLI do
  @moduledoc """
  Command-line interface for the Test Assessment System.

  Provides a programmatic interface for running test assessments with
  various options and output formats.
  """

  alias TestAssessmentApp.Core

  @doc """
  Runs test assessment from command line arguments.
  """
  @spec main([String.t()]) :: :ok | {:error, term()}
  def main(args) do
    case parse_args(args) do
      {:ok, :help} ->
        print_help()
        :ok

      {:ok, :version} ->
        print_version()
        :ok

      {:ok, {project_path, opts}} ->
        run_assessment(project_path, opts)

      {:error, reason} ->
        IO.puts(:stderr, "Error: #{reason}")
        print_usage()
        {:error, reason}
    end
  end

  @doc """
  Runs assessment with progress reporting suitable for CLI usage.
  """
  @spec run_assessment(String.t(), keyword()) :: :ok | {:error, term()}
  def run_assessment(project_path, opts \\ []) do
    format = Keyword.get(opts, :format, :text)
    output_file = Keyword.get(opts, :output_file)
    verbose = Keyword.get(opts, :verbose, false)
    validate_only = Keyword.get(opts, :validate_only, false)

    progress_callback =
      if verbose do
        &verbose_progress/1
      else
        &simple_progress/1
      end

    IO.puts("Test Assessment System")
    IO.puts("Analyzing: #{project_path}")
    IO.puts("")

    if validate_only do
      validate_project_structure(project_path)
    else
      run_full_assessment_cli(project_path, format, output_file, progress_callback)
    end
  end

  # Private functions

  defp parse_args(args) do
    case args do
      ["--help"] -> {:ok, :help}
      ["-h"] -> {:ok, :help}
      ["--version"] -> {:ok, :version}
      ["-v"] -> {:ok, :version}
      _ -> parse_assessment_args(args)
    end
  end

  defp parse_assessment_args(args) do
    {opts, remaining_args, invalid} =
      OptionParser.parse(args,
        switches: [
          format: :string,
          output: :string,
          verbose: :boolean,
          validate_only: :boolean
        ],
        aliases: [
          f: :format,
          o: :output,
          v: :verbose
        ]
      )

    case {remaining_args, invalid} do
      {[project_path], []} ->
        {:ok, {project_path, opts}}

      {[], []} ->
        {:ok, {File.cwd!(), opts}}

      {_, []} when length(remaining_args) > 1 ->
        {:error, "Too many arguments provided"}

      {_, invalid} ->
        {:error, "Invalid options: #{inspect(invalid)}"}
    end
  end

  defp validate_project_structure(project_path) do
    case Core.validate_umbrella_project(project_path) do
      {:ok, apps} ->
        IO.puts("✓ Valid umbrella project structure")
        IO.puts("  Found #{length(apps)} apps:")

        Enum.each(apps, fn app_path ->
          app_name = Path.basename(app_path)
          IO.puts("    - #{app_name}")
        end)

        :ok

      {:error, reason} ->
        IO.puts("✗ Invalid project structure: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp run_full_assessment_cli(project_path, format, output_file, progress_callback) do
    opts = [
      progress_callback: progress_callback,
      format: format,
      output_file: output_file
    ]

    case Core.assess_test_suite(project_path, opts) do
      {:ok, report} ->
        IO.puts("")
        IO.puts("✓ Assessment completed successfully!")

        if output_file do
          IO.puts("Report saved to: #{output_file}")
        else
          print_summary(report)
        end

        :ok

      {:error, reason} ->
        IO.puts("")
        IO.puts("✗ Assessment failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp print_summary(report) do
    IO.puts("")
    IO.puts("Assessment Summary:")
    IO.puts("==================")
    IO.puts("Total tests: #{report.summary.total_tests}")
    IO.puts("Test files: #{report.summary.total_test_files}")
    IO.puts("Apps analyzed: #{report.summary.apps_analyzed}")
    IO.puts("Redundant tests: #{report.summary.redundant_tests_found}")
    IO.puts("Coverage gaps: #{report.summary.coverage_gaps_found}")
    IO.puts("Config issues: #{report.summary.config_issues_found}")
    IO.puts("Overall score: #{Float.round(report.summary.overall_score, 2)}")
  end

  defp simple_progress(message) do
    IO.puts("• #{message}")
  end

  defp verbose_progress(message) do
    timestamp = DateTime.utc_now() |> DateTime.to_time() |> Time.to_string()
    IO.puts("[#{timestamp}] #{message}")
  end

  defp print_help do
    IO.puts("""
    Test Assessment System

    USAGE:
        test_assessment [PROJECT_PATH] [OPTIONS]

    ARGUMENTS:
        PROJECT_PATH    Path to umbrella project (default: current directory)

    OPTIONS:
        -f, --format FORMAT     Output format (text, json, html) [default: text]
        -o, --output FILE       Output file path
        -v, --verbose           Enable verbose output
        --validate-only         Only validate project structure
        -h, --help              Show this help message
        --version               Show version information

    EXAMPLES:
        test_assessment
        test_assessment /path/to/project --format json
        test_assessment --output report.json --verbose
        test_assessment --validate-only
    """)
  end

  defp print_usage do
    IO.puts("Usage: test_assessment [PROJECT_PATH] [OPTIONS]")
    IO.puts("Run 'test_assessment --help' for more information.")
  end

  defp print_version do
    IO.puts("Test Assessment System v0.1.0")
  end
end
