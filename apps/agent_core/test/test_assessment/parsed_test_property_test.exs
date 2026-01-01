defmodule AgentCore.TestAssessment.ParsedTestPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias AgentCore.TestAssessment.ParsedTest

  # Feature: test-assessment, Property 1: ParsedTest field validation
  property "parsed_test.name should always be a non-empty string when valid" do
    check all name <- string(:alphanumeric, min_length: 1, max_length: 100) do
      parsed_test = %ParsedTest{
        name: name,
        file_path: "/test/example.exs",
        line_number: 1,
        test_type: :test,
        setup_blocks: [],
        assertions: [],
        dependencies: [],
        complexity_score: 1.0
      }

      assert is_binary(parsed_test.name)
      assert String.length(parsed_test.name) > 0
    end
  end

  # Feature: test-assessment, Property 2: ParsedTest test_type validation
  property "parsed_test.test_type should be a valid atom" do
    check all test_type <- member_of([:test, :describe, :setup, :property]) do
      parsed_test = %ParsedTest{
        name: "test example",
        file_path: "/test/example.exs",
        line_number: 1,
        test_type: test_type,
        setup_blocks: [],
        assertions: [],
        dependencies: [],
        complexity_score: 1.0
      }

      assert is_atom(parsed_test.test_type)
      assert parsed_test.test_type in [:test, :describe, :setup, :property]
    end
  end

  # Feature: test-assessment, Property 3: ParsedTest complexity_score validation
  property "parsed_test.complexity_score should be a non-negative float" do
    check all complexity <- float(min: 0.0, max: 100.0) do
      parsed_test = %ParsedTest{
        name: "test example",
        file_path: "/test/example.exs",
        line_number: 1,
        test_type: :test,
        setup_blocks: [],
        assertions: [],
        dependencies: [],
        complexity_score: complexity
      }

      assert is_float(parsed_test.complexity_score)
      assert parsed_test.complexity_score >= 0.0
    end
  end

  # Feature: test-assessment, Property 4: ParsedTest file_path validation
  property "parsed_test.file_path should be a valid file path string" do
    check all path_parts <- list_of(string(:alphanumeric, min_length: 1, max_length: 20), min_length: 1, max_length: 5),
              extension <- member_of(["exs", "ex"]) do
      file_path = "/" <> Enum.join(path_parts, "/") <> "." <> extension

      parsed_test = %ParsedTest{
        name: "test example",
        file_path: file_path,
        line_number: 1,
        test_type: :test,
        setup_blocks: [],
        assertions: [],
        dependencies: [],
        complexity_score: 1.0
      }

      assert is_binary(parsed_test.file_path)
      assert String.contains?(parsed_test.file_path, ".")
      assert String.ends_with?(parsed_test.file_path, ".exs") or String.ends_with?(parsed_test.file_path, ".ex")
    end
  end

  # Feature: test-assessment, Property 5: ParsedTest line_number validation
  property "parsed_test.line_number should be a positive integer" do
    check all line_number <- positive_integer() do
      parsed_test = %ParsedTest{
        name: "test example",
        file_path: "/test/example.exs",
        line_number: line_number,
        test_type: :test,
        setup_blocks: [],
        assertions: [],
        dependencies: [],
        complexity_score: 1.0
      }

      assert is_integer(parsed_test.line_number)
      assert parsed_test.line_number > 0
    end
  end

  # Feature: test-assessment, Property 6: ParsedTest list fields validation
  property "parsed_test list fields should always be lists" do
    check all setup_blocks <- list_of(string(:alphanumeric, min_length: 1, max_length: 50)),
              assertions <- list_of(string(:alphanumeric, min_length: 1, max_length: 50)),
              dependencies <- list_of(string(:alphanumeric, min_length: 1, max_length: 30)) do
      parsed_test = %ParsedTest{
        name: "test example",
        file_path: "/test/example.exs",
        line_number: 1,
        test_type: :test,
        setup_blocks: setup_blocks,
        assertions: assertions,
        dependencies: dependencies,
        complexity_score: 1.0
      }

      assert is_list(parsed_test.setup_blocks)
      assert is_list(parsed_test.assertions)
      assert is_list(parsed_test.dependencies)

      # All elements should be strings
      assert Enum.all?(parsed_test.setup_blocks, &is_binary/1)
      assert Enum.all?(parsed_test.assertions, &is_binary/1)
      assert Enum.all?(parsed_test.dependencies, &is_binary/1)
    end
  end

  # Test error conditions
  describe "error conditions" do
    test "handles invalid complexity_score gracefully" do
      # Test with negative complexity score
      assert_raise ArgumentError, fn ->
        %ParsedTest{
          name: "test example",
          file_path: "/test/example.exs",
          line_number: 1,
          test_type: :test,
          setup_blocks: [],
          assertions: [],
          dependencies: [],
          complexity_score: -1.0
        }
        |> validate_complexity_score()
      end
    end

    test "handles invalid line_number gracefully" do
      # Test with zero or negative line number
      assert_raise ArgumentError, fn ->
        %ParsedTest{
          name: "test example",
          file_path: "/test/example.exs",
          line_number: 0,
          test_type: :test,
          setup_blocks: [],
          assertions: [],
          dependencies: [],
          complexity_score: 1.0
        }
        |> validate_line_number()
      end
    end

    test "handles empty name gracefully" do
      # Test with empty name
      assert_raise ArgumentError, fn ->
        %ParsedTest{
          name: "",
          file_path: "/test/example.exs",
          line_number: 1,
          test_type: :test,
          setup_blocks: [],
          assertions: [],
          dependencies: [],
          complexity_score: 1.0
        }
        |> validate_name()
      end
    end
  end

  # Helper validation functions
  defp validate_complexity_score(%ParsedTest{complexity_score: score}) when score < 0 do
    raise ArgumentError, "complexity_score must be non-negative"
  end
  defp validate_complexity_score(parsed_test), do: parsed_test

  defp validate_line_number(%ParsedTest{line_number: line}) when line <= 0 do
    raise ArgumentError, "line_number must be positive"
  end
  defp validate_line_number(parsed_test), do: parsed_test

  defp validate_name(%ParsedTest{name: name}) when name == "" do
    raise ArgumentError, "name cannot be empty"
  end
  defp validate_name(parsed_test), do: parsed_test
end
