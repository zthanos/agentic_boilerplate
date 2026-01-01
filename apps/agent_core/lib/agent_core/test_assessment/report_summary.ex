defmodule AgentCore.TestAssessment.ReportSummary do
  @moduledoc """
  Represents a summary of the test assessment results.
  """

  @derive Jason.Encoder

  @type t :: %__MODULE__{
          total_tests: integer(),
          total_test_files: integer(),
          apps_analyzed: integer(),
          redundant_tests_found: integer(),
          coverage_gaps_found: integer(),
          config_issues_found: integer(),
          overall_score: float()
        }

  defstruct [
    :total_tests,
    :total_test_files,
    :apps_analyzed,
    :redundant_tests_found,
    :coverage_gaps_found,
    :config_issues_found,
    :overall_score
  ]
end
