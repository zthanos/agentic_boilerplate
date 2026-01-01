defmodule AgentCore.TestAssessment.CoverageGap do
  @moduledoc """
  Represents a gap in test coverage that should be addressed.
  """

  @derive Jason.Encoder

  @type gap_type ::
          :untested_function
          | :missing_edge_case
          | :missing_error_condition
          | :untested_component
          | :untested_validation

  @type t :: %__MODULE__{
          module_name: String.t(),
          function_name: String.t() | nil,
          gap_type: gap_type(),
          priority: :low | :medium | :high | :critical,
          description: String.t(),
          suggested_test_type: String.t()
        }

  defstruct [
    :module_name,
    :function_name,
    :gap_type,
    :priority,
    :description,
    :suggested_test_type
  ]
end
