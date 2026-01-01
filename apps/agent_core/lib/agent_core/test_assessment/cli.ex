defmodule AgentCore.TestAssessment.CLI do
  @moduledoc """
  Command-line interface for the Test Assessment System.

  Provides a programmatic interface for running test assessments with
  various options and output formats.
  """

  alias AgentCore.TestAssessment

  @doc """
  Runs test assessment from command line arguments.

  ## Arguments

  - `args` - List of command line arguments

  ## Returns

  - `:ok` on success
  - `{:error, reason}` on failure

  ## Examples

      iex> AgentCore.TestAssessment.CLI.main(["/path/to/project", "--format", "json"])
      :ok

      iex> AgentCore.TestAssessment.CLI.main(["--help"])
      :ok
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
          o: :output
        ]
      )

    cond do
      length(invalid) > 0 ->
        {:error, "Invalid options: #{inspect(invalid)}"}

      length(remaining_args) > 1 ->
        {:error, "Too many arguments. Expected at most one path argument."}

      true ->
        project_path =
          case remaining_args do
            [path] -> Path.expand(path)
            [] -> File.cwd!()
          end

        # Validate format
        format =
          case opts[:format] do
            nil -> :text
            "text" -> :text
            "json" -> :json
            "html" -> :html
            invalid -> {:error, "Invalid format: #{invalid}. Valid formats: text, json, html"}
          end

        parsed_opts = [
          format: format,
          output_file: opts[:output],
          verbose: opts[:verbose] || false,
          validate_only: opts[:validate_only] || false
        ]

        {:ok, {project_path, parsed_opts}}
    end
  end

  defp validate_project_structure(project_path) do
    IO.puts("Validating project structure...")

    case TestAssessment.validate_umbrella_project(project_path) do
      {:ok, apps} ->
        IO.puts("✓ Valid project structure")
        IO.puts("  Found #{length(apps)} app(s):")

        apps
        |> Enum.with_index(1)
        |> Enum.each(fn {app_path, index} ->
          app_name = Path.basename(app_path)
          IO.puts("    #{index}. #{app_name}")
        end)

        IO.puts("")
        IO.puts("Project is ready for assessment.")
        :ok

      {:error, reason} ->
        IO.puts(:stderr, "✗ Invalid project: #{format_validation_error(reason)}")
        {:error, reason}
    end
  end

  defp run_full_assessment_cli(project_path, format, output_file, progress_callback) do
    # Validate first
    case TestAssessment.validate_umbrella_project(project_path) do
      {:ok, _apps} ->
        :ok

      {:error, reason} ->
        IO.puts(:stderr, "✗ Invalid project: #{format_validation_error(reason)}")
        {:error, reason}
    end

    # Run assessment
    opts = [
      progress_callback: progress_callback,
      format: format,
      output_file: output_file
    ]

    case TestAssessment.assess_test_suite(project_path, opts) do
      {:ok, report} ->
        IO.puts("")
        IO.puts("✓ Assessment completed!")
        print_cli_summary(report)

        unless output_file do
          IO.puts("")
          IO.puts("=" |> String.duplicate(60))
          report_content = AgentCore.TestAssessment.ReportGenerator.export_report(report, format)
          IO.puts(report_content)
        end

        :ok

      {:error, reason} ->
        IO.puts(:stderr, "✗ Assessment failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp print_cli_summary(report) do
    summary = report.summary

    IO.puts("")
    IO.puts("Summary:")
    IO.puts("  Tests: #{summary.total_tests} (#{summary.total_test_files} files)")
    IO.puts("  Apps: #{summary.apps_analyzed}")
    IO.puts("  Score: #{Float.round(summary.overall_score, 1)}/100")
    IO.puts("")
    IO.puts("Issues:")
    IO.puts("  Redundant tests: #{summary.redundant_tests_found}")
    IO.puts("  Coverage gaps: #{summary.coverage_gaps_found}")
    IO.puts("  Config issues: #{summary.config_issues_found}")
    IO.puts("  Total recommendations: #{length(report.recommendations)}")

    if output_file = report.output_file do
      IO.puts("")
      IO.puts("Report saved to: #{output_file}")
    end
  end

  defp format_validation_error(reason) do
    case reason do
      :path_not_found -> "Path does not exist"
      :not_directory -> "Path is not a directory"
      :no_valid_apps_found -> "No valid apps found"
      :not_elixir_project -> "Not an Elixir project"
      {:cannot_read_apps_directory, _} -> "Cannot read apps directory"
      {:invalid_project_structure, _} -> "Invalid project structure"
      other -> inspect(other)
    end
  end

  defp verbose_progress(message) do
    timestamp = DateTime.utc_now() |> DateTime.to_time() |> Time.to_string()
    IO.puts("[#{timestamp}] #{message}")
  end

  defp simple_progress(message) do
    IO.puts(message)
  end

  defp print_help do
    IO.puts("""
    Test Assessment System - Analyze and improve your Phoenix test suite

    USAGE:
        test_assessment [PATH] [OPTIONS]

    ARGUMENTS:
        PATH    Path to umbrella project (default: current directory)

    OPTIONS:
        -f, --format FORMAT     Output format: text, json, html (default: text)
        -o, --output FILE       Save report to file (default: stdout)
        --verbose               Show detailed progress
        --validate-only         Only validate project structure
        -h, --help              Show this help
        -v, --version           Show version

    EXAMPLES:
        test_assessment                                    # Assess current directory
        test_assessment /path/to/project                   # Assess specific path
        test_assessment --format json --output report.json # JSON report to file
        test_assessment --verbose                          # Detailed progress
        test_assessment --validate-only                    # Structure check only
    """)
  end

  defp print_usage do
    IO.puts("Usage: test_assessment [PATH] [OPTIONS]")
    IO.puts("Use --help for more information.")
  end

  defp print_version do
    # Get version from mix.exs or default
    version =
      case Application.spec(:agent_core, :vsn) do
        nil -> "dev"
        vsn -> List.to_string(vsn)
      end

    IO.puts("Test Assessment System v#{version}")
  end
end
