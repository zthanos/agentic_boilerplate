defmodule AgentCore.TestAssessment.RefactoringResult do
  @moduledoc """
  Represents the result of refactoring a test file.
  """

  @type t :: %__MODULE__{
          file_path: String.t(),
          original_content: String.t(),
          refactored_content: String.t(),
          changes_applied: [String.t()],
          warnings: [String.t()]
        }

  defstruct [
    :file_path,
    :original_content,
    :refactored_content,
    :changes_applied,
    :warnings
  ]
end
