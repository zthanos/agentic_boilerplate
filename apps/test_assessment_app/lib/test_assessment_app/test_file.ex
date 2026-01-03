defmodule TestAssessmentApp.TestFile do
  @moduledoc """
  Represents a test file discovered in the project structure.
  """

  @type t :: %__MODULE__{
          path: String.t(),
          app_name: String.t(),
          relative_path: String.t(),
          size: integer(),
          last_modified: DateTime.t()
        }

  defstruct [
    :path,
    :app_name,
    :relative_path,
    :size,
    :last_modified
  ]
end
