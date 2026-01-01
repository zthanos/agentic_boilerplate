defmodule AgentCore.TestAssessment.CoverageReport do
  @moduledoc """
  Represents test coverage analysis results.
  """

  @type t :: %__MODULE__{
    total_lines: integer(),
    covered_lines: integer(),
    coverage_percentage: float(),
    uncovered_functions: [String.t()],
    test_coverage_map: %{String.t() => [String.t()]}
  }

  defstruct [
    :total_lines,
    :covered_lines,
    :coverage_percentage,
    :uncovered_functions,
    :test_coverage_map
  ]
end
