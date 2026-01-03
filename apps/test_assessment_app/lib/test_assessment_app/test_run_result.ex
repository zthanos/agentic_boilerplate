defmodule TestAssessmentApp.TestRunResult do
  @moduledoc """
  Represents the result of running the test suite.
  """

  @type t :: %__MODULE__{
          success: boolean(),
          total_tests: integer(),
          passed_tests: integer(),
          failed_tests: integer(),
          execution_time: float(),
          failure_details: [String.t()]
        }

  defstruct [
    :success,
    :total_tests,
    :passed_tests,
    :failed_tests,
    :execution_time,
    :failure_details
  ]
end
