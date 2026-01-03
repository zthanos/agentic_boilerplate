defmodule TestAssessmentApp.Categorization do
  @moduledoc """
  Module responsible for categorizing tests by type and focus area.
  """

  alias TestAssessmentApp.{ParsedTest, TestCategory}

  @spec categorize_test(ParsedTest.t()) :: TestCategory.t()
  def categorize_test(parsed_test) do
    # Implementation migrated from AgentCore.TestAssessment.Categorization
    primary_type = determine_primary_type(parsed_test)

    %TestCategory{
      primary_type: primary_type,
      secondary_types: [],
      confidence_scores: %{primary_type => 1.0},
      focus_areas: []
    }
  end

  defp determine_primary_type(parsed_test) do
    case parsed_test.test_type do
      :test -> :unit
      :describe -> :integration
      _ -> :unit
    end
  end
end
