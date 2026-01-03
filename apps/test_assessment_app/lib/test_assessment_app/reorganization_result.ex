defmodule TestAssessmentApp.ReorganizationResult do
  @moduledoc """
  Represents the result of test file reorganization.
  """

  @type t :: %__MODULE__{
          moved_files: %{String.t() => String.t()},
          created_directories: [String.t()],
          updated_imports: [String.t()],
          conflicts: [String.t()]
        }

  defstruct [
    :moved_files,
    :created_directories,
    :updated_imports,
    :conflicts
  ]
end
