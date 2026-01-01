defmodule AgentCore.TestAssessment.RedundancyFinding do
  @moduledoc """
  Represents a finding of redundant tests in the test suite.
  """

  @derive Jason.Encoder

  @type t :: %__MODULE__{
          test_names: [String.t()],
          redundancy_type: :identical_coverage | :similar_logic | :duplicate_assertions,
          confidence_score: float(),
          recommended_action: String.t(),
          justification: String.t()
        }

  defstruct [
    :test_names,
    :redundancy_type,
    :confidence_score,
    :recommended_action,
    :justification
  ]
end
