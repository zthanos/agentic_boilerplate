defmodule TestAssessmentApp.ParsedTest do
  @moduledoc """
  Represents a parsed test with extracted metadata.
  """

  @type t :: %__MODULE__{
          name: String.t(),
          file_path: String.t(),
          line_number: integer(),
          test_type: atom(),
          setup_blocks: [String.t()],
          assertions: [String.t()],
          dependencies: [String.t()],
          complexity_score: float()
        }

  defstruct [
    :name,
    :file_path,
    :line_number,
    :test_type,
    :setup_blocks,
    :assertions,
    :dependencies,
    :complexity_score
  ]
end
