defmodule AgentCore.TestAssessment.ConfigValidator do
  @moduledoc """
  Module responsible for validating test configurations across umbrella apps.
  """

  require Logger
  alias AgentCore.TestAssessment.{ConfigIssue, FileDiscovery}

  @required_test_deps [:ex_machina, :mox, :stream_data]
  @common_test_deps [:phoenix_live_view, :phoenix_ecto, :ecto_sql]

  @doc """
  Validates mix.exs test dependencies across all apps in the umbrella.
  """
  @spec validate_mix_dependencies(String.t()) :: [ConfigIssue.t()]
  def validate_mix_dependencies(umbrella_path) do
    case FileDiscovery.discover_config_files(umbrella_path) do
      {:ok, config_files} ->
        config_files
        |> Enum.filter(&(&1.filename == "mix.exs"))
        |> Enum.flat_map(&validate_mix_file/1)

      {:error, reason} ->
        Logger.error("Failed to discover config files: #{inspect(reason)}")

        [
          create_config_issue(
            "umbrella",
            umbrella_path,
            :missing_dependency,
            :critical,
            "Failed to discover configuration files",
            "Check umbrella project structure"
          )
        ]
    end
  end

  @doc """
  Validates test.exs configuration consistency across apps.
  """
  @spec validate_test_configs(String.t()) :: [ConfigIssue.t()]
  def validate_test_configs(umbrella_path) do
    case FileDiscovery.discover_config_files(umbrella_path) do
      {:ok, config_files} ->
        test_configs = Enum.filter(config_files, &(&1.filename == "test.exs"))
        validate_test_config_consistency(test_configs)

      {:error, reason} ->
        Logger.error("Failed to discover test config files: #{inspect(reason)}")

        [
          create_config_issue(
            "umbrella",
            umbrella_path,
            :inconsistent_config,
            :error,
            "Failed to discover test configuration files",
            "Check config directory structure"
          )
        ]
    end
  end

  @doc """
  Validates Phoenix-specific database and environment configurations.
  """
  @spec validate_phoenix_configs(String.t()) :: [ConfigIssue.t()]
  def validate_phoenix_configs(umbrella_path) do
    case FileDiscovery.discover_config_files(umbrella_path) do
      {:ok, config_files} ->
        config_files
        |> Enum.filter(&(&1.filename in ["test.exs", "config.exs"]))
        |> Enum.flat_map(&validate_phoenix_config/1)

      {:error, reason} ->
        Logger.error("Failed to discover Phoenix config files: #{inspect(reason)}")

        [
          create_config_issue(
            "umbrella",
            umbrella_path,
            :invalid_setting,
            :error,
            "Failed to discover Phoenix configuration files",
            "Check Phoenix app structure"
          )
        ]
    end
  end

  @doc """
  Reports configuration mismatches between umbrella and app-level configs.
  """
  @spec report_config_mismatches(String.t()) :: [ConfigIssue.t()]
  def report_config_mismatches(umbrella_path) do
    case FileDiscovery.discover_config_files(umbrella_path) do
      {:ok, config_files} ->
        umbrella_configs = Enum.filter(config_files, &(&1.context == "umbrella"))
        app_configs = Enum.filter(config_files, &(&1.context != "umbrella"))

        compare_config_consistency(umbrella_configs, app_configs)

      {:error, reason} ->
        Logger.error("Failed to discover configs for mismatch analysis: #{inspect(reason)}")

        [
          create_config_issue(
            "umbrella",
            umbrella_path,
            :inconsistent_config,
            :warning,
            "Failed to analyze configuration consistency",
            "Check project structure"
          )
        ]
    end
  end

  # Private helper functions

  @spec validate_mix_file(map()) :: [ConfigIssue.t()]
  defp validate_mix_file(config_file) do
    case File.read(config_file.path) do
      {:ok, content} ->
        issues = []
        issues = issues ++ check_test_dependencies(content, config_file)
        issues = issues ++ check_test_environments(content, config_file)
        issues

      {:error, reason} ->
        Logger.warning("Failed to read mix.exs file #{config_file.path}: #{inspect(reason)}")

        [
          create_config_issue(
            config_file.context,
            config_file.path,
            :missing_dependency,
            :error,
            "Cannot read mix.exs file",
            "Check file permissions and existence"
          )
        ]
    end
  end

  @spec check_test_dependencies(String.t(), map()) :: [ConfigIssue.t()]
  defp check_test_dependencies(content, config_file) do
    issues = []

    # Check for required test dependencies
    missing_deps =
      @required_test_deps
      |> Enum.filter(fn dep ->
        !String.contains?(content, ":#{dep}")
      end)

    missing_issues =
      missing_deps
      |> Enum.map(fn dep ->
        create_config_issue(
          config_file.context,
          config_file.path,
          :missing_dependency,
          :warning,
          "Missing recommended test dependency: #{dep}",
          "Add {:#{dep}, \"~> x.x\", only: :test} to deps"
        )
      end)

    # Check for test-only dependencies not properly scoped
    test_only_issues = check_test_only_scope(content, config_file)

    issues ++ missing_issues ++ test_only_issues
  end

  @spec check_test_only_scope(String.t(), map()) :: [ConfigIssue.t()]
  defp check_test_only_scope(content, config_file) do
    test_deps = @required_test_deps ++ @common_test_deps

    test_deps
    |> Enum.filter(fn dep ->
      String.contains?(content, ":#{dep}") and
        !String.contains?(content, "only: :test") and
        !String.contains?(content, "only: [:test")
    end)
    |> Enum.map(fn dep ->
      create_config_issue(
        config_file.context,
        config_file.path,
        :invalid_setting,
        :warning,
        "Test dependency #{dep} should be scoped to test environment only",
        "Add 'only: :test' to the #{dep} dependency"
      )
    end)
  end

  @spec check_test_environments(String.t(), map()) :: [ConfigIssue.t()]
  defp check_test_environments(content, config_file) do
    # Check for test environment configuration
    unless String.contains?(content, "test:") or String.contains?(content, ":test") do
      [
        create_config_issue(
          config_file.context,
          config_file.path,
          :missing_dependency,
          :warning,
          "No test environment configuration found",
          "Add test environment settings in mix.exs"
        )
      ]
    else
      []
    end
  end

  @spec validate_test_config_consistency([map()]) :: [ConfigIssue.t()]
  defp validate_test_config_consistency(test_configs) do
    case test_configs do
      [] ->
        [
          create_config_issue(
            "umbrella",
            "N/A",
            :missing_dependency,
            :error,
            "No test.exs configuration files found",
            "Create test.exs files in config directories"
          )
        ]

      configs ->
        # Group configs by app and compare settings
        configs
        |> Enum.group_by(& &1.context)
        |> Enum.flat_map(fn {_context, app_configs} ->
          validate_app_test_configs(app_configs)
        end)
    end
  end

  @spec validate_app_test_configs([map()]) :: [ConfigIssue.t()]
  defp validate_app_test_configs(configs) do
    configs
    |> Enum.flat_map(fn config ->
      case File.read(config.path) do
        {:ok, content} ->
          validate_test_config_content(content, config)

        {:error, reason} ->
          Logger.warning("Failed to read test config #{config.path}: #{inspect(reason)}")

          [
            create_config_issue(
              config.context,
              config.path,
              :inconsistent_config,
              :error,
              "Cannot read test.exs file",
              "Check file permissions"
            )
          ]
      end
    end)
  end

  @spec validate_test_config_content(String.t(), map()) :: [ConfigIssue.t()]
  defp validate_test_config_content(content, config) do
    issues = []

    # Check for database configuration
    issues =
      if String.contains?(content, "database:") or String.contains?(content, "repo") do
        issues
      else
        [
          create_config_issue(
            config.context,
            config.path,
            :missing_dependency,
            :warning,
            "No database configuration found in test.exs",
            "Add database configuration for test environment"
          )
          | issues
        ]
      end

    # Check for logger configuration
    issues =
      if String.contains?(content, "logger") do
        issues
      else
        [
          create_config_issue(
            config.context,
            config.path,
            :invalid_setting,
            :warning,
            "No logger configuration found in test.exs",
            "Add logger configuration to control test output"
          )
          | issues
        ]
      end

    issues
  end

  @spec validate_phoenix_config(map()) :: [ConfigIssue.t()]
  defp validate_phoenix_config(config_file) do
    case File.read(config_file.path) do
      {:ok, content} ->
        issues = []
        issues = issues ++ check_phoenix_database_config(content, config_file)
        issues = issues ++ check_phoenix_endpoint_config(content, config_file)
        issues = issues ++ check_phoenix_test_settings(content, config_file)
        issues

      {:error, reason} ->
        Logger.warning("Failed to read Phoenix config #{config_file.path}: #{inspect(reason)}")

        [
          create_config_issue(
            config_file.context,
            config_file.path,
            :invalid_setting,
            :error,
            "Cannot read Phoenix configuration file",
            "Check file permissions"
          )
        ]
    end
  end

  @spec check_phoenix_database_config(String.t(), map()) :: [ConfigIssue.t()]
  defp check_phoenix_database_config(content, config_file) do
    # Check for test database configuration
    if String.contains?(content, "database:") and config_file.filename == "test.exs" do
      naming_issues =
        unless String.contains?(content, "_test") do
          [
            create_config_issue(
              config_file.context,
              config_file.path,
              :invalid_setting,
              :warning,
              "Test database should have '_test' suffix",
              "Rename test database to include '_test' suffix"
            )
          ]
        else
          []
        end

      # Check for pool configuration
      pool_issues =
        unless String.contains?(content, "pool:") do
          [
            create_config_issue(
              config_file.context,
              config_file.path,
              :missing_dependency,
              :warning,
              "Missing database pool configuration in test environment",
              "Add pool: Ecto.Adapters.SQL.Sandbox to test database config"
            )
          ]
        else
          []
        end

      naming_issues ++ pool_issues
    else
      []
    end
  end

  @spec check_phoenix_endpoint_config(String.t(), map()) :: [ConfigIssue.t()]
  defp check_phoenix_endpoint_config(content, config_file) do
    if String.contains?(content, "Endpoint") and config_file.filename == "test.exs" do
      # Check for test server configuration
      unless String.contains?(content, "server: false") do
        [
          create_config_issue(
            config_file.context,
            config_file.path,
            :invalid_setting,
            :warning,
            "Phoenix endpoint should have server: false in test environment",
            "Add server: false to endpoint configuration"
          )
        ]
      else
        []
      end
    else
      []
    end
  end

  @spec check_phoenix_test_settings(String.t(), map()) :: [ConfigIssue.t()]
  defp check_phoenix_test_settings(content, config_file) do
    if config_file.filename == "test.exs" do
      exunit_issues =
        unless String.contains?(content, "ExUnit") do
          [
            create_config_issue(
              config_file.context,
              config_file.path,
              :missing_dependency,
              :warning,
              "Missing ExUnit configuration in test.exs",
              "Add ExUnit.start() and configure test options"
            )
          ]
        else
          []
        end

      # Check for Ecto sandbox mode
      sandbox_issues =
        if String.contains?(content, "Ecto") and !String.contains?(content, "Sandbox") do
          [
            create_config_issue(
              config_file.context,
              config_file.path,
              :invalid_setting,
              :warning,
              "Missing Ecto Sandbox configuration for tests",
              "Add Ecto.Adapters.SQL.Sandbox.mode configuration"
            )
          ]
        else
          []
        end

      exunit_issues ++ sandbox_issues
    else
      []
    end
  end

  @spec compare_config_consistency([map()], [map()]) :: [ConfigIssue.t()]
  defp compare_config_consistency(umbrella_configs, app_configs) do
    issues = []

    # Compare mix.exs files between umbrella and apps
    umbrella_mix = Enum.find(umbrella_configs, &(&1.filename == "mix.exs"))
    app_mix_files = Enum.filter(app_configs, &(&1.filename == "mix.exs"))

    issues =
      if umbrella_mix do
        issues ++ compare_mix_dependencies(umbrella_mix, app_mix_files)
      else
        issues
      end

    # Compare test configurations
    umbrella_test = Enum.find(umbrella_configs, &(&1.filename == "test.exs"))
    app_test_files = Enum.filter(app_configs, &(&1.filename == "test.exs"))

    issues =
      if umbrella_test do
        issues ++ compare_test_configurations(umbrella_test, app_test_files)
      else
        issues
      end

    issues
  end

  @spec compare_mix_dependencies(map(), [map()]) :: [ConfigIssue.t()]
  defp compare_mix_dependencies(umbrella_mix, app_mix_files) do
    case File.read(umbrella_mix.path) do
      {:ok, umbrella_content} ->
        app_mix_files
        |> Enum.flat_map(fn app_mix ->
          case File.read(app_mix.path) do
            {:ok, app_content} ->
              check_dependency_consistency(umbrella_content, app_content, app_mix)

            {:error, _reason} ->
              [
                create_config_issue(
                  app_mix.context,
                  app_mix.path,
                  :inconsistent_config,
                  :error,
                  "Cannot read app mix.exs for consistency check",
                  "Check file permissions"
                )
              ]
          end
        end)

      {:error, _reason} ->
        [
          create_config_issue(
            "umbrella",
            umbrella_mix.path,
            :inconsistent_config,
            :error,
            "Cannot read umbrella mix.exs for consistency check",
            "Check file permissions"
          )
        ]
    end
  end

  @spec check_dependency_consistency(String.t(), String.t(), map()) :: [ConfigIssue.t()]
  defp check_dependency_consistency(umbrella_content, app_content, app_config) do
    # Extract Elixir version consistency
    issues = []

    umbrella_elixir = extract_elixir_version(umbrella_content)
    app_elixir = extract_elixir_version(app_content)

    issues =
      if umbrella_elixir && app_elixir && umbrella_elixir != app_elixir do
        [
          create_config_issue(
            app_config.context,
            app_config.path,
            :inconsistent_config,
            :warning,
            "Elixir version mismatch: umbrella has #{umbrella_elixir}, app has #{app_elixir}",
            "Align Elixir versions between umbrella and app"
          )
          | issues
        ]
      else
        issues
      end

    issues
  end

  @spec compare_test_configurations(map(), [map()]) :: [ConfigIssue.t()]
  defp compare_test_configurations(_umbrella_test, app_test_files) do
    # For now, just check that all apps have test configurations
    # More sophisticated comparison could be added later
    app_test_files
    |> Enum.flat_map(fn test_config ->
      case File.read(test_config.path) do
        {:ok, _content} ->
          # Configuration exists and is readable
          []

        {:error, _reason} ->
          [
            create_config_issue(
              test_config.context,
              test_config.path,
              :inconsistent_config,
              :warning,
              "Test configuration file is not readable",
              "Check file permissions and syntax"
            )
          ]
      end
    end)
  end

  @spec extract_elixir_version(String.t()) :: String.t() | nil
  defp extract_elixir_version(content) do
    case Regex.run(~r/elixir:\s*"([^"]+)"/, content) do
      [_, version] -> version
      _ -> nil
    end
  end

  @spec create_config_issue(
          String.t(),
          String.t(),
          ConfigIssue.issue_type(),
          :warning | :error | :critical,
          String.t(),
          String.t()
        ) :: ConfigIssue.t()
  defp create_config_issue(app_name, file_path, issue_type, severity, description, suggested_fix) do
    %ConfigIssue{
      app_name: app_name,
      file_path: file_path,
      issue_type: issue_type,
      severity: severity,
      description: description,
      suggested_fix: suggested_fix
    }
  end
end
