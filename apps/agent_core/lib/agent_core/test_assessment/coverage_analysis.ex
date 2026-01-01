defmodule AgentCore.TestAssessment.CoverageAnalysis do
  @moduledoc """
  Module responsible for analyzing test coverage and calculating value scores.
  """

  alias AgentCore.TestAssessment.{ParsedTest, CoverageReport, CoverageGap}

  @doc """
  Analyzes coverage for a collection of parsed tests.

  Determines which code paths each test exercises and generates
  a comprehensive coverage report.
  """
  @spec analyze_coverage([ParsedTest.t()]) :: CoverageReport.t()
  def analyze_coverage(parsed_tests) do
    test_coverage_map = build_test_coverage_map(parsed_tests)
    all_covered_paths = extract_all_covered_paths(test_coverage_map)

    # Calculate coverage statistics
    total_lines = calculate_total_lines(parsed_tests)
    covered_lines = length(all_covered_paths)
    coverage_percentage = if total_lines > 0, do: covered_lines / total_lines * 100, else: 0.0

    # Identify uncovered functions from test dependencies and assertions
    uncovered_functions = identify_uncovered_functions(parsed_tests, all_covered_paths)

    %CoverageReport{
      total_lines: total_lines,
      covered_lines: covered_lines,
      coverage_percentage: coverage_percentage,
      uncovered_functions: uncovered_functions,
      test_coverage_map: test_coverage_map
    }
  end

  @doc """
  Calculates a value score for a test based on coverage uniqueness and quality.

  The value score considers:
  - Coverage uniqueness (how many unique code paths this test covers)
  - Test quality (complexity, assertions, setup)
  - Redundancy factor (how much overlap with other tests)
  """
  @spec calculate_value_score(ParsedTest.t(), CoverageReport.t()) :: float()
  def calculate_value_score(test, coverage_report) do
    test_paths = Map.get(coverage_report.test_coverage_map, test.name, [])

    # Base score from coverage uniqueness
    uniqueness_score = calculate_uniqueness_score(test_paths, coverage_report.test_coverage_map)

    # Quality multiplier based on test characteristics
    quality_multiplier = calculate_quality_multiplier(test)

    # Combine scores with weights
    base_score = uniqueness_score * quality_multiplier

    # Normalize to 0-100 scale
    min(base_score * 10, 100.0)
  end

  @doc """
  Identifies coverage gaps in the codebase.

  Returns a list of CoverageGap structs representing untested functions,
  missing edge cases, and error conditions.
  """
  @spec identify_coverage_gaps(CoverageReport.t()) :: [CoverageGap.t()]
  def identify_coverage_gaps(coverage_report) do
    uncovered_function_gaps = create_uncovered_function_gaps(coverage_report.uncovered_functions)
    edge_case_gaps = identify_edge_case_gaps(coverage_report)
    error_condition_gaps = identify_error_condition_gaps(coverage_report)

    uncovered_function_gaps ++ edge_case_gaps ++ error_condition_gaps
  end

  @doc """
  Analyzes code paths that each test exercises based on dependencies and assertions.
  """
  @spec analyze_test_code_paths(ParsedTest.t()) :: [String.t()]
  def analyze_test_code_paths(test) do
    # Extract code paths from test dependencies (imports, aliases)
    dependency_paths = extract_dependency_paths(test.dependencies)

    # Extract code paths from assertions (function calls, module references)
    assertion_paths = extract_assertion_paths(test.assertions)

    # Extract paths from setup blocks
    setup_paths = extract_setup_paths(test.setup_blocks)

    (dependency_paths ++ assertion_paths ++ setup_paths)
    |> Enum.uniq()
    |> Enum.filter(&valid_code_path?/1)
  end

  # Private helper functions

  defp build_test_coverage_map(parsed_tests) do
    parsed_tests
    |> Enum.reduce(%{}, fn test, acc ->
      code_paths = analyze_test_code_paths(test)
      Map.put(acc, test.name, code_paths)
    end)
  end

  defp extract_all_covered_paths(test_coverage_map) do
    test_coverage_map
    |> Map.values()
    |> List.flatten()
    |> Enum.uniq()
  end

  defp calculate_total_lines(parsed_tests) do
    # Estimate total lines based on complexity scores and test count
    # This is a heuristic since we don't have actual source code analysis
    base_lines = length(parsed_tests) * 50  # Average lines per test file
    complexity_bonus = parsed_tests
                      |> Enum.map(& &1.complexity_score)
                      |> Enum.sum()
                      |> round()

    base_lines + complexity_bonus
  end

  defp identify_uncovered_functions(parsed_tests, covered_paths) do
    # Extract all function references from tests
    all_referenced_functions =
      parsed_tests
      |> Enum.flat_map(fn test ->
        test.dependencies ++ test.assertions ++ test.setup_blocks
      end)
      |> Enum.flat_map(&extract_function_references/1)
      |> Enum.uniq()

    # Find functions that are referenced but not in covered paths
    all_referenced_functions -- covered_paths
  end

  defp calculate_uniqueness_score(test_paths, test_coverage_map) do
    if Enum.empty?(test_paths) do
      0.0
    else
      # Count how many tests cover each path
      path_coverage_counts =
        test_coverage_map
        |> Map.values()
        |> List.flatten()
        |> Enum.frequencies()

      # Calculate uniqueness: paths covered by fewer tests are more valuable
      unique_score =
        test_paths
        |> Enum.map(fn path ->
          coverage_count = Map.get(path_coverage_counts, path, 1)
          1.0 / coverage_count  # More unique = higher score
        end)
        |> Enum.sum()

      unique_score / length(test_paths)  # Average uniqueness
    end
  end

  defp calculate_quality_multiplier(test) do
    # Base quality from complexity
    complexity_factor = min(test.complexity_score / 10.0, 2.0)  # Cap at 2x

    # Assertion quality (more assertions = better coverage)
    assertion_factor = min(length(test.assertions) / 5.0, 1.5)  # Cap at 1.5x

    # Setup quality (proper setup indicates thorough testing)
    setup_factor = if length(test.setup_blocks) > 0, do: 1.2, else: 1.0

    # Test type factor (integration tests generally more valuable)
    type_factor = case test.test_type do
      :integration -> 1.3
      :property_based -> 1.4
      :end_to_end -> 1.5
      _ -> 1.0
    end

    complexity_factor * assertion_factor * setup_factor * type_factor
  end

  defp create_uncovered_function_gaps(uncovered_functions) do
    uncovered_functions
    |> Enum.map(fn function_path ->
      {module_name, function_name} = parse_function_path(function_path)

      %CoverageGap{
        module_name: module_name,
        function_name: function_name,
        gap_type: :untested_function,
        priority: determine_function_priority(function_path),
        description: "Function #{function_path} has no test coverage",
        suggested_test_type: "unit test"
      }
    end)
  end

  defp identify_edge_case_gaps(coverage_report) do
    # Identify potential edge cases based on function patterns
    coverage_report.test_coverage_map
    |> Map.values()
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.filter(&likely_needs_edge_case_testing?/1)
    |> Enum.map(fn path ->
      {module_name, function_name} = parse_function_path(path)

      %CoverageGap{
        module_name: module_name,
        function_name: function_name,
        gap_type: :missing_edge_case,
        priority: :medium,
        description: "Function #{path} may need edge case testing (empty inputs, boundary values)",
        suggested_test_type: "property-based test"
      }
    end)
  end

  defp identify_error_condition_gaps(coverage_report) do
    # Identify functions that likely need error condition testing
    coverage_report.test_coverage_map
    |> Map.values()
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.filter(&likely_needs_error_testing?/1)
    |> Enum.map(fn path ->
      {module_name, function_name} = parse_function_path(path)

      %CoverageGap{
        module_name: module_name,
        function_name: function_name,
        gap_type: :missing_error_condition,
        priority: :high,
        description: "Function #{path} may need error condition testing (invalid inputs, failure scenarios)",
        suggested_test_type: "unit test with error cases"
      }
    end)
  end

  defp extract_dependency_paths(dependencies) do
    dependencies
    |> Enum.flat_map(&parse_dependency_for_paths/1)
  end

  defp extract_assertion_paths(assertions) do
    assertions
    |> Enum.flat_map(&parse_assertion_for_paths/1)
  end

  defp extract_setup_paths(setup_blocks) do
    setup_blocks
    |> Enum.flat_map(&parse_setup_for_paths/1)
  end

  defp parse_dependency_for_paths(dependency) do
    # Extract module and function references from dependency strings
    # Handle patterns like "alias MyApp.Module" or "import MyApp.Module"
    case String.split(dependency) do
      ["alias", module] -> [module]
      ["import", module] -> [module]
      ["use", module] -> [module]
      _ -> []
    end
  end

  defp parse_assertion_for_paths(assertion) do
    # Extract function calls and module references from assertion strings
    # This is a simplified parser - in practice would need more sophisticated AST analysis
    assertion
    |> String.split(~r/[^a-zA-Z0-9_\.]/)
    |> Enum.filter(&String.contains?(&1, "."))
    |> Enum.filter(&valid_code_path?/1)
  end

  defp parse_setup_for_paths(setup_block) do
    # Extract code paths from setup blocks
    setup_block
    |> String.split(~r/[^a-zA-Z0-9_\.]/)
    |> Enum.filter(&String.contains?(&1, "."))
    |> Enum.filter(&valid_code_path?/1)
  end

  defp valid_code_path?(path) do
    # Basic validation for code paths
    String.length(path) > 3 and
    String.contains?(path, ".") and
    not String.starts_with?(path, ".") and
    not String.ends_with?(path, ".")
  end

  defp extract_function_references(text) do
    # Extract function references from text (simplified)
    text
    |> String.split(~r/[^a-zA-Z0-9_\.]/)
    |> Enum.filter(&String.contains?(&1, "."))
    |> Enum.filter(&valid_code_path?/1)
  end

  defp parse_function_path(function_path) do
    case String.split(function_path, ".", parts: 2) do
      [module, function] -> {module, function}
      [single] -> {single, nil}
    end
  end

  defp determine_function_priority(function_path) do
    cond do
      String.contains?(function_path, "Controller") -> :high
      String.contains?(function_path, "LiveView") -> :high
      String.contains?(function_path, "Schema") -> :medium
      String.contains?(function_path, "Context") -> :high
      true -> :medium
    end
  end

  defp likely_needs_edge_case_testing?(path) do
    # Functions that commonly need edge case testing
    String.contains?(path, "parse") or
    String.contains?(path, "validate") or
    String.contains?(path, "transform") or
    String.contains?(path, "convert") or
    String.contains?(path, "calculate")
  end

  defp likely_needs_error_testing?(path) do
    # Functions that commonly need error condition testing
    String.contains?(path, "create") or
    String.contains?(path, "update") or
    String.contains?(path, "delete") or
    String.contains?(path, "fetch") or
    String.contains?(path, "get") or
    String.contains?(path, "parse") or
    String.contains?(path, "validate")
  end
end
