defmodule AgentCore.TestAssessment.TestParserTest do
  use ExUnit.Case, async: true

  alias AgentCore.TestAssessment.TestParser
  alias AgentCore.TestAssessment.ParsedTest

  describe "parse_test_file/1" do
    test "parses a simple test file with basic tests" do
      # Create a temporary test file
      test_content = """
      defmodule MyTest do
        use ExUnit.Case

        test "simple test" do
          assert 1 + 1 == 2
        end

        test "another test" do
          assert true
          refute false
        end
      end
      """

      temp_file = create_temp_file(test_content)

      try do
        {:ok, parsed_tests} = TestParser.parse_test_file(temp_file)

        assert length(parsed_tests) == 2

        # Check first test
        first_test = Enum.at(parsed_tests, 0)
        assert first_test.name == "simple test"
        assert first_test.test_type == :test
        assert first_test.line_number > 0
        assert length(first_test.assertions) == 1
        assert first_test.complexity_score > 0.0

        # Check second test
        second_test = Enum.at(parsed_tests, 1)
        assert second_test.name == "another test"
        assert second_test.test_type == :test
        assert length(second_test.assertions) == 2
      after
        File.rm(temp_file)
      end
    end

    test "parses test file with describe blocks" do
      test_content = """
      defmodule MyTest do
        use ExUnit.Case

        describe "user operations" do
          test "creates user" do
            assert true
          end

          test "updates user" do
            assert false == false
          end
        end

        describe "admin operations" do
          test "admin can delete" do
            refute false
          end
        end
      end
      """

      temp_file = create_temp_file(test_content)

      try do
        {:ok, parsed_tests} = TestParser.parse_test_file(temp_file)

        # Should find describe blocks and tests
        describe_blocks = Enum.filter(parsed_tests, &(&1.test_type == :describe))
        test_blocks = Enum.filter(parsed_tests, &(&1.test_type == :test))

        assert length(describe_blocks) == 2
        assert length(test_blocks) == 3

        # Check describe block names
        describe_names = Enum.map(describe_blocks, & &1.name)
        assert "user operations" in describe_names
        assert "admin operations" in describe_names
      after
        File.rm(temp_file)
      end
    end

    test "parses test file with setup blocks" do
      test_content = """
      defmodule MyTest do
        use ExUnit.Case

        setup do
          {:ok, user: %{name: "test"}}
        end

        setup_all do
          start_supervised!(MyApp.Server)
          :ok
        end

        test "uses setup" do
          assert true
        end
      end
      """

      temp_file = create_temp_file(test_content)

      try do
        {:ok, parsed_tests} = TestParser.parse_test_file(temp_file)

        setup_blocks = Enum.filter(parsed_tests, &(&1.test_type in [:setup, :setup_all]))
        test_blocks = Enum.filter(parsed_tests, &(&1.test_type == :test))

        assert length(setup_blocks) == 2
        assert length(test_blocks) == 1

        # Check setup types
        setup_types = Enum.map(setup_blocks, & &1.test_type)
        assert :setup in setup_types
        assert :setup_all in setup_types
      after
        File.rm(temp_file)
      end
    end

    test "handles malformed files with fallback parsing" do
      # Create a file with syntax errors that will trigger fallback
      malformed_content = """
      defmodule MyTest do
        use ExUnit.Case

        test "valid test" do
          assert 1 == 1
        end

        # This will cause AST parsing to fail
        test "broken syntax" do
          assert 1 ==
        end
      """

      temp_file = create_temp_file(malformed_content)

      try do
        {:ok, parsed_tests} = TestParser.parse_test_file(temp_file)

        # Should still find at least the valid test using fallback parsing
        assert length(parsed_tests) >= 1

        test_names = Enum.map(parsed_tests, & &1.name)
        assert "valid test" in test_names
      after
        File.rm(temp_file)
      end
    end

    test "handles non-existent files gracefully" do
      non_existent_file = "/path/to/non/existent/file.exs"

      {:error, reason} = TestParser.parse_test_file(non_existent_file)

      assert reason == :enoent
    end
  end

  describe "extract_test_metadata/2" do
    test "extracts metadata from test AST node" do
      ast = {:test, [line: 5], ["sample test", [do: {:assert, [line: 6], [true]}]]}
      file_path = "/path/to/test.exs"

      parsed_test = TestParser.extract_test_metadata(ast, file_path)

      assert parsed_test.name == "sample test"
      assert parsed_test.file_path == file_path
      assert parsed_test.line_number == 5
      assert parsed_test.test_type == :test
      assert parsed_test.complexity_score > 0.0
    end

    test "extracts metadata from describe AST node" do
      ast = {:describe, [line: 10], ["user tests", [do: {:__block__, [], []}]]}
      file_path = "/path/to/test.exs"

      parsed_test = TestParser.extract_test_metadata(ast, file_path)

      assert parsed_test.name == "user tests"
      assert parsed_test.file_path == file_path
      assert parsed_test.line_number == 10
      assert parsed_test.test_type == :describe
    end

    test "extracts metadata from setup AST node" do
      ast = {:setup, [line: 3], [[do: {:ok, [], []}]]}
      file_path = "/path/to/test.exs"

      parsed_test = TestParser.extract_test_metadata(ast, file_path)

      assert parsed_test.name == "setup"
      assert parsed_test.file_path == file_path
      assert parsed_test.line_number == 3
      assert parsed_test.test_type == :setup
    end

    test "handles unknown AST nodes gracefully" do
      ast = {:unknown_macro, [line: 1], []}
      file_path = "/path/to/test.exs"

      parsed_test = TestParser.extract_test_metadata(ast, file_path)

      assert parsed_test.name == "unknown"
      assert parsed_test.test_type == :unknown
      assert parsed_test.complexity_score == 0.0
    end
  end

  describe "calculate_complexity_score/1" do
    test "calculates complexity for simple test" do
      ast = {:test, [], ["simple", [do: {:assert, [], [true]}]]}

      score = TestParser.calculate_complexity_score(ast)

      # Base score + assertion
      assert score > 1.0
      # Should not be too complex
      assert score < 3.0
    end

    test "calculates higher complexity for nested test" do
      # Test with multiple assertions and conditionals
      ast =
        {:test, [],
         [
           "complex test",
           [
             do:
               {:__block__, [],
                [
                  {:if, [], [true, [do: {:assert, [], [true]}]]},
                  {:case, [], [1, [do: [{:->, [], [[1], {:assert, [], [true]}]}]]]},
                  {:assert, [], [false]}
                ]}
           ]
         ]}

      score = TestParser.calculate_complexity_score(ast)

      # Should be more complex due to nesting and conditionals
      assert score > 3.0
    end

    test "returns base score for empty test" do
      ast = {:test, [], ["empty", [do: nil]]}

      score = TestParser.calculate_complexity_score(ast)

      # The base score is 1.0, but there might be some nesting depth counted
      # Should be at least base score
      assert score >= 1.0
      # Should not be too complex for empty test
      assert score <= 2.0
    end
  end

  # Helper function to create temporary test files
  defp create_temp_file(content) do
    temp_file = Path.join(System.tmp_dir!(), "test_#{:rand.uniform(10000)}.exs")
    File.write!(temp_file, content)
    temp_file
  end
end
