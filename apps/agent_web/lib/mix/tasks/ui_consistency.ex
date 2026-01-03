defmodule Mix.Tasks.UiConsistency do
  @moduledoc """
  Mix task for validating UI consistency in the agent testing interface.

  ## Usage

      # Run full UI consistency check
      mix ui_consistency

      # Run quick check
      mix ui_consistency --quick

      # Check specific component
      mix ui_consistency --component path/to/component.ex

      # Show recommendations
      mix ui_consistency --recommendations

      # Generate detailed report
      mix ui_consistency --report
  """

  use Mix.Task
  alias AgentWeb.UIConsistencyChecker
  alias AgentWeb.UIConsistencyValidator

  @shortdoc "Validates UI consistency across agent testing interface components"

  def run(args) do
    # Start the application to ensure modules are loaded
    Mix.Task.run("app.start")

    case args do
      [] ->
        run_full_check()

      ["--quick"] ->
        run_quick_check()

      ["--component", file_path] ->
        check_component(file_path)

      ["--recommendations"] ->
        show_recommendations()

      ["--report"] ->
        generate_report()

      ["--help"] ->
        show_help()

      _ ->
        Mix.shell().error("Invalid arguments. Use --help for usage information.")
    end
  end

  defp run_full_check do
    Mix.shell().info("Running full UI consistency check...")
    UIConsistencyChecker.run_full_check()
  end

  defp run_quick_check do
    Mix.shell().info("Running quick UI consistency check...")

    case UIConsistencyChecker.quick_check() do
      :ok ->
        Mix.shell().info("✅ All components pass UI consistency checks")

      :error ->
        Mix.shell().error("❌ Some components have UI consistency issues")
        Mix.shell().info("Run 'mix ui_consistency' for detailed analysis")
    end
  end

  defp check_component(file_path) do
    Mix.shell().info("Checking UI consistency for: #{file_path}")

    case UIConsistencyChecker.check_component_file(file_path) do
      :ok ->
        Mix.shell().info("✅ Component passes UI consistency checks")

      :error ->
        Mix.shell().error("❌ Component has UI consistency issues")
    end
  end

  defp show_recommendations do
    recommendations = UIConsistencyChecker.get_recommendations()
    Mix.shell().info(recommendations)
  end

  defp generate_report do
    Mix.shell().info("Generating UI consistency report...")
    report = UIConsistencyValidator.generate_consistency_report()
    Mix.shell().info(report)

    # Optionally save to file
    report_file = "ui_consistency_report.md"
    File.write!(report_file, report)
    Mix.shell().info("Report saved to: #{report_file}")
  end

  defp show_help do
    Mix.shell().info("""
    UI Consistency Checker

    This task validates UI consistency across the agent testing interface components,
    ensuring adherence to the established design system patterns.

    Usage:
      mix ui_consistency                           # Run full consistency check
      mix ui_consistency --quick                   # Run quick check
      mix ui_consistency --component <file>        # Check specific component
      mix ui_consistency --recommendations         # Show improvement recommendations
      mix ui_consistency --report                  # Generate detailed report
      mix ui_consistency --help                    # Show this help

    Examples:
      mix ui_consistency
      mix ui_consistency --quick
      mix ui_consistency --component apps/agent_web/lib/agent_web_web/live/agent_testing_live.ex
      mix ui_consistency --recommendations
      mix ui_consistency --report

    The checker validates:
    - DaisyUI + Tailwind CSS design system compliance
    - Responsive design patterns
    - Color consistency and semantic usage
    - Component reuse and styling consistency
    - Accessibility standards
    """)
  end
end
