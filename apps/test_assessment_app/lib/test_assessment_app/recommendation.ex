defmodule TestAssessmentApp.Recommendation do
  @moduledoc """
  Represents an actionable recommendation for improving the test suite.
  """

  @derive Jason.Encoder

  @type recommendation_type ::
          :refactor_test | :add_test | :remove_test | :update_config | :modernize_pattern

  @type t :: %__MODULE__{
          type: recommendation_type(),
          priority: :low | :medium | :high | :critical,
          title: String.t(),
          description: String.t(),
          affected_files: [String.t()],
          estimated_effort: :small | :medium | :large,
          justification: String.t()
        }

  defstruct [
    :type,
    :priority,
    :title,
    :description,
    :affected_files,
    :estimated_effort,
    :justification
  ]
end
