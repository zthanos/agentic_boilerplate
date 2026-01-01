defmodule AgentCore.TestAssessment.TestParser do
  @moduledoc """
  Module responsible for parsing Elixir test files and extracting test metadata.
  """

  require Logger
  alias AgentCore.TestAssessment.ParsedTest

  @test_macros [:test, :describe, :setup, :setup_all]
  @assertion_functions [
    :assert,
    :assert_receive,
    :assert_received,
    :refute,
    :refute_receive,
    :refute_received
  ]

  @doc """
  Parses a test file and extracts all test metadata.

  Uses AST analysis to extract test names, line numbers, test types,
  assertions, dependencies, and complexity scores.
  """
  @spec parse_test_file(String.t()) :: {:ok, [ParsedTest.t()]} | {:error, term()}
  def parse_test_file(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        case parse_content(content, file_path) do
          {:ok, parsed_tests} ->
            {:ok, parsed_tests}

          {:error, reason} ->
            Logger.warning("Failed to parse #{file_path}: #{inspect(reason)}")
            # Fallback strategy: try pattern matching approach
            fallback_parse(content, file_path)
        end

      {:error, reason} ->
        Logger.error("Failed to read file #{file_path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Extracts test metadata from an AST node.
  """
  @spec extract_test_metadata(Macro.t(), String.t()) :: ParsedTest.t()
  def extract_test_metadata(ast, file_path) do
    case ast do
      {:test, meta, [test_name | _]} when is_binary(test_name) ->
        line_number = Keyword.get(meta, :line, 0)
        assertions = extract_assertions(ast)
        dependencies = extract_dependencies(ast)
        complexity_score = calculate_complexity_score(ast)

        %ParsedTest{
          name: test_name,
          file_path: file_path,
          line_number: line_number,
          test_type: :test,
          setup_blocks: [],
          assertions: assertions,
          dependencies: dependencies,
          complexity_score: complexity_score
        }

      {:describe, meta, [describe_name | _]} when is_binary(describe_name) ->
        line_number = Keyword.get(meta, :line, 0)
        dependencies = extract_dependencies(ast)
        complexity_score = calculate_complexity_score(ast)

        %ParsedTest{
          name: describe_name,
          file_path: file_path,
          line_number: line_number,
          test_type: :describe,
          setup_blocks: [],
          assertions: [],
          dependencies: dependencies,
          complexity_score: complexity_score
        }

      {:setup, meta, _} ->
        line_number = Keyword.get(meta, :line, 0)
        dependencies = extract_dependencies(ast)
        complexity_score = calculate_complexity_score(ast)

        %ParsedTest{
          name: "setup",
          file_path: file_path,
          line_number: line_number,
          test_type: :setup,
          setup_blocks: [],
          assertions: [],
          dependencies: dependencies,
          complexity_score: complexity_score
        }

      {:setup_all, meta, _} ->
        line_number = Keyword.get(meta, :line, 0)
        dependencies = extract_dependencies(ast)
        complexity_score = calculate_complexity_score(ast)

        %ParsedTest{
          name: "setup_all",
          file_path: file_path,
          line_number: line_number,
          test_type: :setup_all,
          setup_blocks: [],
          assertions: [],
          dependencies: dependencies,
          complexity_score: complexity_score
        }

      _ ->
        %ParsedTest{
          name: "unknown",
          file_path: file_path,
          line_number: 0,
          test_type: :unknown,
          setup_blocks: [],
          assertions: [],
          dependencies: [],
          complexity_score: 0.0
        }
    end
  end

  @doc """
  Calculates complexity score for a test based on its structure.
  """
  @spec calculate_complexity_score(Macro.t()) :: float()
  def calculate_complexity_score(ast) do
    base_score = 1.0
    assertion_count = count_assertions(ast)
    nesting_depth = calculate_nesting_depth(ast)
    conditional_count = count_conditionals(ast)

    # Calculate complexity based on various factors
    complexity =
      base_score +
        assertion_count * 0.5 +
        nesting_depth * 1.0 +
        conditional_count * 0.8

    Float.round(complexity, 2)
  end

  # Private functions

  @spec parse_content(String.t(), String.t()) :: {:ok, [ParsedTest.t()]} | {:error, term()}
  defp parse_content(content, file_path) do
    try do
      case Code.string_to_quoted(content) do
        {:ok, ast} ->
          parsed_tests = extract_all_tests(ast, file_path)
          {:ok, parsed_tests}

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      error ->
        {:error, error}
    end
  end

  @spec extract_all_tests(Macro.t(), String.t()) :: [ParsedTest.t()]
  defp extract_all_tests(ast, file_path) do
    ast
    |> Macro.prewalk([], fn node, acc ->
      case node do
        {macro, _meta, _args} when macro in @test_macros ->
          parsed_test = extract_test_metadata(node, file_path)
          {node, [parsed_test | acc]}

        _ ->
          {node, acc}
      end
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  @spec extract_assertions(Macro.t()) :: [String.t()]
  defp extract_assertions(ast) do
    ast
    |> Macro.prewalk([], fn node, acc ->
      case node do
        {assertion, _meta, _args} when assertion in @assertion_functions ->
          assertion_str = Macro.to_string(node)
          {node, [assertion_str | acc]}

        _ ->
          {node, acc}
      end
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  @spec extract_dependencies(Macro.t()) :: [String.t()]
  defp extract_dependencies(ast) do
    dependencies = []

    # Extract import statements
    import_deps = extract_imports(ast)

    # Extract alias statements
    alias_deps = extract_aliases(ast)

    # Extract module references
    module_deps = extract_module_references(ast)

    (dependencies ++ import_deps ++ alias_deps ++ module_deps)
    |> Enum.uniq()
  end

  @spec extract_imports(Macro.t()) :: [String.t()]
  defp extract_imports(ast) do
    ast
    |> Macro.prewalk([], fn node, acc ->
      case node do
        {:import, _meta, [module]} when is_atom(module) ->
          {node, [Atom.to_string(module) | acc]}

        {:import, _meta, [{:__aliases__, _meta2, aliases}]} ->
          module_name = aliases |> Enum.map(&Atom.to_string/1) |> Enum.join(".")
          {node, [module_name | acc]}

        _ ->
          {node, acc}
      end
    end)
    |> elem(1)
  end

  @spec extract_aliases(Macro.t()) :: [String.t()]
  defp extract_aliases(ast) do
    ast
    |> Macro.prewalk([], fn node, acc ->
      case node do
        {:alias, _meta, [module]} when is_atom(module) ->
          {node, [Atom.to_string(module) | acc]}

        {:alias, _meta, [{:__aliases__, _meta2, aliases}]} ->
          module_name = aliases |> Enum.map(&Atom.to_string/1) |> Enum.join(".")
          {node, [module_name | acc]}

        _ ->
          {node, acc}
      end
    end)
    |> elem(1)
  end

  @spec extract_module_references(Macro.t()) :: [String.t()]
  defp extract_module_references(ast) do
    ast
    |> Macro.prewalk([], fn node, acc ->
      case node do
        {{:., _meta, [{:__aliases__, _meta2, aliases}, _function]}, _meta3, _args} ->
          module_name = aliases |> Enum.map(&Atom.to_string/1) |> Enum.join(".")
          {node, [module_name | acc]}

        _ ->
          {node, acc}
      end
    end)
    |> elem(1)
  end

  @spec count_assertions(Macro.t()) :: integer()
  defp count_assertions(ast) do
    ast
    |> Macro.prewalk(0, fn node, acc ->
      case node do
        {assertion, _meta, _args} when assertion in @assertion_functions ->
          {node, acc + 1}

        _ ->
          {node, acc}
      end
    end)
    |> elem(1)
  end

  @spec calculate_nesting_depth(Macro.t()) :: integer()
  defp calculate_nesting_depth(ast) do
    calculate_depth(ast, 0)
  end

  @spec calculate_depth(Macro.t(), integer()) :: integer()
  defp calculate_depth(ast, current_depth) do
    case ast do
      {_name, _meta, args} when is_list(args) ->
        max_child_depth =
          args
          |> Enum.map(&calculate_depth(&1, current_depth + 1))
          |> Enum.max(fn -> current_depth end)

        max(current_depth, max_child_depth)

      list when is_list(list) ->
        max_child_depth =
          list
          |> Enum.map(&calculate_depth(&1, current_depth))
          |> Enum.max(fn -> current_depth end)

        max_child_depth

      _ ->
        current_depth
    end
  end

  @spec count_conditionals(Macro.t()) :: integer()
  defp count_conditionals(ast) do
    ast
    |> Macro.prewalk(0, fn node, acc ->
      case node do
        {:if, _meta, _args} ->
          {node, acc + 1}

        {:unless, _meta, _args} ->
          {node, acc + 1}

        {:case, _meta, _args} ->
          {node, acc + 1}

        {:cond, _meta, _args} ->
          {node, acc + 1}

        {:with, _meta, _args} ->
          {node, acc + 1}

        _ ->
          {node, acc}
      end
    end)
    |> elem(1)
  end

  @spec fallback_parse(String.t(), String.t()) :: {:ok, [ParsedTest.t()]} | {:error, term()}
  defp fallback_parse(content, file_path) do
    Logger.info("Using fallback pattern matching parser for #{file_path}")

    try do
      lines = String.split(content, "\n")
      parsed_tests = extract_tests_by_pattern(lines, file_path)
      {:ok, parsed_tests}
    rescue
      error ->
        Logger.error("Fallback parsing failed for #{file_path}: #{inspect(error)}")
        {:error, error}
    end
  end

  @spec extract_tests_by_pattern([String.t()], String.t()) :: [ParsedTest.t()]
  defp extract_tests_by_pattern(lines, file_path) do
    lines
    |> Enum.with_index(1)
    |> Enum.reduce([], fn {line, line_number}, acc ->
      cond do
        String.match?(line, ~r/^\s*test\s+"([^"]+)"/) ->
          test_name = extract_test_name_from_line(line)

          parsed_test = %ParsedTest{
            name: test_name,
            file_path: file_path,
            line_number: line_number,
            test_type: :test,
            setup_blocks: [],
            assertions: [],
            dependencies: [],
            complexity_score: 1.0
          }

          [parsed_test | acc]

        String.match?(line, ~r/^\s*describe\s+"([^"]+)"/) ->
          describe_name = extract_test_name_from_line(line)

          parsed_test = %ParsedTest{
            name: describe_name,
            file_path: file_path,
            line_number: line_number,
            test_type: :describe,
            setup_blocks: [],
            assertions: [],
            dependencies: [],
            complexity_score: 1.0
          }

          [parsed_test | acc]

        String.match?(line, ~r/^\s*setup(_all)?\s+do/) ->
          setup_type = if String.contains?(line, "setup_all"), do: :setup_all, else: :setup

          parsed_test = %ParsedTest{
            name: Atom.to_string(setup_type),
            file_path: file_path,
            line_number: line_number,
            test_type: setup_type,
            setup_blocks: [],
            assertions: [],
            dependencies: [],
            complexity_score: 1.0
          }

          [parsed_test | acc]

        true ->
          acc
      end
    end)
    |> Enum.reverse()
  end

  @spec extract_test_name_from_line(String.t()) :: String.t()
  defp extract_test_name_from_line(line) do
    case Regex.run(~r/"([^"]+)"/, line) do
      [_, test_name] -> test_name
      _ -> "unknown"
    end
  end
end
