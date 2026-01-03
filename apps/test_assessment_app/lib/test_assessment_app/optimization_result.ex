defmodule TestAssessmentApp.OptimizationResult do
  @moduledoc """
  Represents the result of a test suite optimization operation.
  """

  alias TestAssessmentApp.TestRunResult

  @type t :: %__MODULE__{
          removed_files: [String.t()],
          modified_files: [String.t()],
          reorganized_files: %{String.t() => String.t()},
          backup_directory: String.t(),
          test_run_result: TestRunResult.t(),
          optimization_summary: String.t()
        }

  defstruct [
    :removed_files,
    :modified_files,
    :reorganized_files,
    :backup_directory,
    :test_run_result,
    :optimization_summary
  ]
end
