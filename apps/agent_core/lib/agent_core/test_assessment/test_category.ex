defmodule AgentCore.TestAssessment.TestCategory do
  @moduledoc """
  Represents the categorization of a test with confidence scores.
  """

  @derive Jason.Encoder

  @type category_type :: :unit | :integration | :property_based | :end_to_end

  @type t :: %__MODULE__{
          primary_type: category_type(),
          secondary_types: [category_type()],
          confidence_scores: %{category_type() => float()},
          focus_areas: [String.t()]
        }

  defstruct [
    :primary_type,
    :secondary_types,
    :confidence_scores,
    :focus_areas
  ]
end
