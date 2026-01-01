defmodule AgentCore.TestAssessment.Categorization do
  @moduledoc """
  Module responsible for categorizing tests by type and focus area.
  """

  alias AgentCore.TestAssessment.{ParsedTest, TestCategory}

  # Patterns for identifying different test types
  @unit_test_patterns [
    ~r/test.*unit/i,
    ~r/describe.*unit/i,
    ~r/assert.*==|assert.*!=|refute/,
    ~r/ExUnit\.Case/
  ]

  @integration_test_patterns [
    ~r/test.*integration/i,
    ~r/describe.*integration/i,
    ~r/Ecto\.Repo/,
    ~r/Phoenix\.ConnTest/,
    ~r/get.*conn|post.*conn|put.*conn|delete.*conn/,
    ~r/Plug\.Test/
  ]

  @property_based_patterns [
    ~r/property.*test/i,
    ~r/StreamData/,
    ~r/check.*all/,
    ~r/forall/i,
    ~r/property.*"/
  ]

  @end_to_end_patterns [
    ~r/test.*e2e|test.*end.*to.*end/i,
    ~r/Phoenix\.LiveViewTest/,
    ~r/render.*submit|render.*click/,
    ~r/live.*view|mount.*live/,
    ~r/browser.*test/i
  ]

  # Focus area patterns
  @focus_area_patterns %{
    "authentication" => [~r/auth|login|logout|session/i],
    "database" => [~r/repo|ecto|query|changeset/i],
    "api" => [~r/api|endpoint|controller|json/i],
    "ui" => [~r/live.*view|component|template|render/i],
    "validation" => [~r/valid|changeset.*error|validate/i],
    "business_logic" => [~r/service|domain|logic/i],
    "performance" => [~r/benchmark|performance|speed/i],
    "security" => [~r/security|csrf|xss|injection/i]
  }

  @doc """
  Categorizes a test based on its patterns and structure.

  Classifies tests as unit, integration, property-based, or end-to-end
  and assigns focus area tags.
  """
  @spec categorize_test(ParsedTest.t()) :: TestCategory.t()
  def categorize_test(parsed_test) do
    test_content = build_test_content(parsed_test)

    # Calculate confidence scores for each category
    confidence_scores = %{
      unit: calculate_pattern_confidence(test_content, @unit_test_patterns),
      integration: calculate_pattern_confidence(test_content, @integration_test_patterns),
      property_based: calculate_pattern_confidence(test_content, @property_based_patterns),
      end_to_end: calculate_pattern_confidence(test_content, @end_to_end_patterns)
    }

    # Determine primary and secondary types
    {primary_type, secondary_types} = determine_types(confidence_scores)

    # Extract focus areas
    focus_areas = extract_focus_areas(test_content)

    %TestCategory{
      primary_type: primary_type,
      secondary_types: secondary_types,
      confidence_scores: confidence_scores,
      focus_areas: focus_areas
    }
    |> assign_confidence_score()
  end

  @doc """
  Assigns confidence scores for test categorization.
  """
  @spec assign_confidence_score(TestCategory.t()) :: TestCategory.t()
  def assign_confidence_score(category) do
    # Normalize confidence scores to ensure they sum to 1.0
    total_confidence =
      category.confidence_scores
      |> Map.values()
      |> Enum.sum()

    normalized_scores =
      if total_confidence > 0 do
        category.confidence_scores
        |> Enum.map(fn {type, score} -> {type, score / total_confidence} end)
        |> Enum.into(%{})
      else
        # Default to unit test if no patterns match
        %{unit: 1.0, integration: 0.0, property_based: 0.0, end_to_end: 0.0}
      end

    %{category | confidence_scores: normalized_scores}
  end

  @doc """
  Groups similar tests together based on patterns.
  """
  @spec group_similar_tests([ParsedTest.t()]) :: %{String.t() => [ParsedTest.t()]}
  def group_similar_tests(parsed_tests) do
    parsed_tests
    |> Enum.group_by(&extract_test_pattern/1)
    |> Enum.into(%{}, fn {pattern, tests} ->
      group_name = generate_group_name(pattern, tests)
      {group_name, tests}
    end)
  end

  # Private helper functions

  defp build_test_content(parsed_test) do
    [
      parsed_test.name,
      parsed_test.file_path,
      Enum.join(parsed_test.setup_blocks, " "),
      Enum.join(parsed_test.assertions, " "),
      Enum.join(parsed_test.dependencies, " ")
    ]
    |> Enum.join(" ")
  end

  defp calculate_pattern_confidence(content, patterns) do
    matches =
      patterns
      |> Enum.map(&count_pattern_matches(content, &1))
      |> Enum.sum()

    # Convert match count to confidence score (0.0 to 1.0)
    case matches do
      0 -> 0.0
      n when n >= 3 -> 1.0
      n -> n / 3.0
    end
  end

  defp count_pattern_matches(content, pattern) do
    case Regex.scan(pattern, content) do
      [] -> 0
      matches -> length(matches)
    end
  end

  defp determine_types(confidence_scores) do
    # Sort by confidence score descending
    sorted_scores =
      confidence_scores
      |> Enum.sort_by(fn {_type, score} -> score end, :desc)

    case sorted_scores do
      [{primary_type, primary_score} | rest] when primary_score > 0.0 ->
        # Include secondary types with confidence > 0.3
        secondary_types =
          rest
          |> Enum.filter(fn {_type, score} -> score > 0.3 end)
          |> Enum.map(fn {type, _score} -> type end)

        {primary_type, secondary_types}

      _ ->
        # Default to unit test if no clear pattern
        {:unit, []}
    end
  end

  defp extract_focus_areas(content) do
    @focus_area_patterns
    |> Enum.filter(fn {_area, patterns} ->
      Enum.any?(patterns, &Regex.match?(&1, content))
    end)
    |> Enum.map(fn {area, _patterns} -> area end)
  end

  defp extract_test_pattern(parsed_test) do
    # Extract pattern based on test structure and naming
    base_pattern =
      cond do
        String.contains?(parsed_test.name, "property") -> "property_test"
        String.contains?(parsed_test.name, "integration") -> "integration_test"
        String.contains?(parsed_test.name, "e2e") -> "e2e_test"
        length(parsed_test.assertions) > 5 -> "complex_test"
        length(parsed_test.setup_blocks) > 2 -> "setup_heavy_test"
        true -> "standard_test"
      end

    # Add focus area to pattern if detected
    focus_areas = extract_focus_areas(build_test_content(parsed_test))

    case focus_areas do
      [area | _] -> "#{base_pattern}_#{area}"
      [] -> base_pattern
    end
  end

  defp generate_group_name(pattern, tests) do
    test_count = length(tests)

    case pattern do
      "property_test" <> _ -> "Property-based Tests (#{test_count})"
      "integration_test" <> _ -> "Integration Tests (#{test_count})"
      "e2e_test" <> _ -> "End-to-End Tests (#{test_count})"
      "complex_test" <> _ -> "Complex Tests (#{test_count})"
      "setup_heavy_test" <> _ -> "Setup-Heavy Tests (#{test_count})"
      pattern -> "#{String.replace(pattern, "_", " ") |> String.capitalize()} (#{test_count})"
    end
  end
end
