defmodule TestAssessmentApp.FileDiscovery do
  @moduledoc """
  Module responsible for discovering test files and configuration files
  across umbrella project structure.
  """

  require Logger
  alias TestAssessmentApp.TestFile

  @test_file_patterns ["*_test.exs", "*test.exs"]
  @config_file_patterns [
    "mix.exs",
    "test.exs",
    "config.exs",
    "dev.exs",
    "prod.exs",
    "runtime.exs"
  ]

  @doc """
  Discovers all test files in the given umbrella project path.

  Recursively scans all apps in the umbrella structure to locate test files,
  extracting metadata such as file size, modification time, and relative paths.
  """
  @spec discover_test_files(String.t()) :: {:ok, [TestFile.t()]} | {:error, term()}
  def discover_test_files(umbrella_path) do
    with {:ok, apps} <- discover_umbrella_apps(umbrella_path) do
      test_files =
        apps
        |> Enum.flat_map(fn app_path ->
          app_name = Path.basename(app_path)
          discover_test_files_in_app(app_path, app_name)
        end)
        |> Enum.filter(&(&1 != nil))

      {:ok, test_files}
    else
      {:error, reason} ->
        Logger.error("Failed to discover test files in #{umbrella_path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Discovers all configuration files relevant to testing in the umbrella project.

  Locates mix.exs, test.exs, and other configuration files across all apps.
  """
  @spec discover_config_files(String.t()) :: {:ok, [map()]} | {:error, term()}
  def discover_config_files(umbrella_path) do
    with {:ok, apps} <- discover_umbrella_apps(umbrella_path) do
      # Discover config files at umbrella root level
      umbrella_configs = discover_config_files_in_path(umbrella_path, "umbrella")

      # Discover config files in each app
      app_configs =
        apps
        |> Enum.flat_map(fn app_path ->
          app_name = Path.basename(app_path)
          discover_config_files_in_path(app_path, app_name)
        end)

      all_configs = umbrella_configs ++ app_configs
      {:ok, all_configs}
    else
      {:error, reason} ->
        Logger.error("Failed to discover config files in #{umbrella_path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Extracts metadata from a discovered file.
  """
  @spec extract_file_metadata(String.t(), String.t()) :: {:ok, TestFile.t()} | {:error, term()}
  def extract_file_metadata(file_path, app_name) do
    case File.stat(file_path) do
      {:ok, %File.Stat{size: size, mtime: mtime}} ->
        # Convert erlang datetime to DateTime
        last_modified = mtime |> NaiveDateTime.from_erl!() |> DateTime.from_naive!("Etc/UTC")

        # Calculate relative path from app root
        relative_path = calculate_relative_path(file_path, app_name)

        test_file = %TestFile{
          path: file_path,
          app_name: app_name,
          relative_path: relative_path,
          size: size,
          last_modified: last_modified
        }

        {:ok, test_file}

      {:error, reason} ->
        Logger.warning("Failed to extract metadata for #{file_path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Private functions

  @spec discover_umbrella_apps(String.t()) :: {:ok, [String.t()]} | {:error, term()}
  defp discover_umbrella_apps(umbrella_path) do
    apps_path = Path.join(umbrella_path, "apps")

    case File.exists?(apps_path) do
      true ->
        case File.ls(apps_path) do
          {:ok, entries} ->
            apps =
              entries
              |> Enum.map(&Path.join(apps_path, &1))
              |> Enum.filter(&File.dir?/1)
              |> Enum.filter(&has_mix_file?/1)

            {:ok, apps}

          {:error, reason} ->
            Logger.error("Failed to list apps directory #{apps_path}: #{inspect(reason)}")
            {:error, reason}
        end

      false ->
        # Not an umbrella project, treat as single app
        if has_mix_file?(umbrella_path) do
          {:ok, [umbrella_path]}
        else
          {:error, :not_elixir_project}
        end
    end
  end

  @spec discover_test_files_in_app(String.t(), String.t()) :: [TestFile.t()]
  defp discover_test_files_in_app(app_path, app_name) do
    test_path = Path.join(app_path, "test")

    case File.exists?(test_path) do
      true ->
        @test_file_patterns
        |> Enum.flat_map(fn pattern ->
          discover_files_by_pattern(test_path, pattern)
        end)
        |> Enum.uniq()
        |> Enum.map(fn file_path ->
          case extract_file_metadata(file_path, app_name) do
            {:ok, test_file} -> test_file
            {:error, _reason} -> nil
          end
        end)
        |> Enum.filter(&(&1 != nil))

      false ->
        Logger.info("No test directory found in app #{app_name} at #{test_path}")
        []
    end
  end

  @spec discover_config_files_in_path(String.t(), String.t()) :: [map()]
  defp discover_config_files_in_path(base_path, context) do
    # Check for config files in the base path
    base_configs = find_config_files_in_directory(base_path, context)

    # Check for config files in config subdirectory
    config_path = Path.join(base_path, "config")

    config_dir_configs =
      case File.exists?(config_path) do
        true -> find_config_files_in_directory(config_path, context)
        false -> []
      end

    base_configs ++ config_dir_configs
  end

  @spec find_config_files_in_directory(String.t(), String.t()) :: [map()]
  defp find_config_files_in_directory(directory, context) do
    @config_file_patterns
    |> Enum.flat_map(fn pattern ->
      file_path = Path.join(directory, pattern)

      case File.exists?(file_path) do
        true ->
          case File.stat(file_path) do
            {:ok, %File.Stat{size: size, mtime: mtime}} ->
              last_modified =
                mtime |> NaiveDateTime.from_erl!() |> DateTime.from_naive!("Etc/UTC")

              [
                %{
                  path: file_path,
                  context: context,
                  filename: pattern,
                  size: size,
                  last_modified: last_modified
                }
              ]

            {:error, reason} ->
              Logger.warning("Failed to stat config file #{file_path}: #{inspect(reason)}")
              []
          end

        false ->
          []
      end
    end)
  end

  @spec discover_files_by_pattern(String.t(), String.t()) :: [String.t()]
  defp discover_files_by_pattern(directory, pattern) do
    case File.ls(directory) do
      {:ok, entries} ->
        # Find files matching pattern in current directory
        direct_matches =
          entries
          |> Enum.filter(&match_pattern?(&1, pattern))
          |> Enum.map(&Path.join(directory, &1))
          |> Enum.filter(&File.regular?/1)

        # Recursively search subdirectories
        subdirectory_matches =
          entries
          |> Enum.map(&Path.join(directory, &1))
          |> Enum.filter(&File.dir?/1)
          |> Enum.flat_map(&discover_files_by_pattern(&1, pattern))

        direct_matches ++ subdirectory_matches

      {:error, reason} ->
        Logger.warning("Failed to list directory #{directory}: #{inspect(reason)}")
        []
    end
  end

  @spec match_pattern?(String.t(), String.t()) :: boolean()
  defp match_pattern?(filename, pattern) do
    # Convert glob pattern to regex
    # First escape dots, then replace * with .*
    regex_pattern =
      pattern
      |> String.replace(".", "\\.")
      |> String.replace("*", ".*")

    case Regex.compile("^#{regex_pattern}$") do
      {:ok, regex} -> Regex.match?(regex, filename)
      {:error, _} -> false
    end
  end

  @spec has_mix_file?(String.t()) :: boolean()
  defp has_mix_file?(path) do
    mix_file = Path.join(path, "mix.exs")
    File.exists?(mix_file)
  end

  @spec calculate_relative_path(String.t(), String.t()) :: String.t()
  defp calculate_relative_path(file_path, app_name) do
    # Find the app directory in the path and calculate relative path from there
    path_parts = Path.split(file_path)

    case Enum.find_index(path_parts, &(&1 == app_name)) do
      nil ->
        # Fallback: use filename if app name not found in path
        Path.basename(file_path)

      app_index ->
        # Take parts after the app name
        path_parts
        |> Enum.drop(app_index + 1)
        |> Path.join()
    end
  end
end
