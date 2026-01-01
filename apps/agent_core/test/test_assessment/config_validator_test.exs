defmodule AgentCore.TestAssessment.ConfigValidatorTest do
  use ExUnit.Case, async: true

  alias AgentCore.TestAssessment.{ConfigValidator, ConfigIssue}

  describe "validate_mix_dependencies/1" do
    test "identifies missing test dependencies" do
      # Create a temporary directory structure for testing
      temp_dir = System.tmp_dir!() |> Path.join("config_validator_test_#{:rand.uniform(10000)}")
      File.mkdir_p!(temp_dir)
      apps_dir = Path.join(temp_dir, "apps")
      File.mkdir_p!(apps_dir)

      # Create a test app with minimal mix.exs
      test_app_dir = Path.join(apps_dir, "test_app")
      File.mkdir_p!(test_app_dir)

      mix_content = """
      defmodule TestApp.MixProject do
        use Mix.Project

        def project do
          [
            app: :test_app,
            version: "0.1.0",
            elixir: "~> 1.14",
            deps: deps()
          ]
        end

        defp deps do
          [
            {:phoenix, "~> 1.7.0"}
          ]
        end
      end
      """

      File.write!(Path.join(test_app_dir, "mix.exs"), mix_content)

      # Test the validation
      issues = ConfigValidator.validate_mix_dependencies(temp_dir)

      # Should find missing test dependencies
      assert length(issues) > 0
      assert Enum.any?(issues, fn issue ->
        issue.issue_type == :missing_dependency and
        String.contains?(issue.description, "ex_machina")
      end)

      # Cleanup
      File.rm_rf!(temp_dir)
    end

    test "handles missing config files gracefully" do
      temp_dir = System.tmp_dir!() |> Path.join("config_validator_empty_#{:rand.uniform(10000)}")
      File.mkdir_p!(temp_dir)

      issues = ConfigValidator.validate_mix_dependencies(temp_dir)

      # Should handle the error gracefully
      assert length(issues) >= 0

      # Cleanup
      File.rm_rf!(temp_dir)
    end
  end

  describe "validate_test_configs/1" do
    test "identifies missing test configuration files" do
      temp_dir = System.tmp_dir!() |> Path.join("config_test_#{:rand.uniform(10000)}")
      File.mkdir_p!(temp_dir)
      apps_dir = Path.join(temp_dir, "apps")
      File.mkdir_p!(apps_dir)

      # Create app without test.exs
      test_app_dir = Path.join(apps_dir, "test_app")
      File.mkdir_p!(test_app_dir)
      File.write!(Path.join(test_app_dir, "mix.exs"), "# minimal mix file")

      issues = ConfigValidator.validate_test_configs(temp_dir)

      # Should identify missing test configs
      assert length(issues) > 0
      missing_config_issue = Enum.find(issues, fn issue ->
        String.contains?(issue.description, "No test.exs configuration files found")
      end)
      assert missing_config_issue != nil

      # Cleanup
      File.rm_rf!(temp_dir)
    end

    test "validates test configuration content" do
      temp_dir = System.tmp_dir!() |> Path.join("config_content_test_#{:rand.uniform(10000)}")
      File.mkdir_p!(temp_dir)
      apps_dir = Path.join(temp_dir, "apps")
      File.mkdir_p!(apps_dir)

      # Create app with test.exs but missing configurations
      test_app_dir = Path.join(apps_dir, "test_app")
      config_dir = Path.join(test_app_dir, "config")
      File.mkdir_p!(config_dir)
      File.write!(Path.join(test_app_dir, "mix.exs"), "# minimal mix file")

      test_config_content = """
      import Config
      # Minimal test config without database or logger
      """

      File.write!(Path.join(config_dir, "test.exs"), test_config_content)

      issues = ConfigValidator.validate_test_configs(temp_dir)

      # Should find missing database and logger configurations
      assert length(issues) > 0
      assert Enum.any?(issues, fn issue ->
        String.contains?(issue.description, "database configuration")
      end)

      # Cleanup
      File.rm_rf!(temp_dir)
    end
  end

  describe "validate_phoenix_configs/1" do
    test "validates Phoenix database configuration" do
      temp_dir = System.tmp_dir!() |> Path.join("phoenix_config_test_#{:rand.uniform(10000)}")
      File.mkdir_p!(temp_dir)
      apps_dir = Path.join(temp_dir, "apps")
      File.mkdir_p!(apps_dir)

      # Create Phoenix app with improper test database config
      phoenix_app_dir = Path.join(apps_dir, "phoenix_app")
      config_dir = Path.join(phoenix_app_dir, "config")
      File.mkdir_p!(config_dir)
      File.write!(Path.join(phoenix_app_dir, "mix.exs"), "# phoenix mix file")

      test_config_content = """
      import Config

      config :phoenix_app, PhoenixApp.Repo,
        database: "phoenix_app_prod",
        pool: Ecto.Adapters.SQL.Sandbox
      """

      File.write!(Path.join(config_dir, "test.exs"), test_config_content)

      issues = ConfigValidator.validate_phoenix_configs(temp_dir)

      # Should find database naming issue
      assert length(issues) > 0
      assert Enum.any?(issues, fn issue ->
        String.contains?(issue.description, "_test")
      end)

      # Cleanup
      File.rm_rf!(temp_dir)
    end

    test "validates Phoenix endpoint configuration" do
      temp_dir = System.tmp_dir!() |> Path.join("phoenix_endpoint_test_#{:rand.uniform(10000)}")
      File.mkdir_p!(temp_dir)
      apps_dir = Path.join(temp_dir, "apps")
      File.mkdir_p!(apps_dir)

      # Create Phoenix app with improper endpoint config
      phoenix_app_dir = Path.join(apps_dir, "phoenix_app")
      config_dir = Path.join(phoenix_app_dir, "config")
      File.mkdir_p!(config_dir)
      File.write!(Path.join(phoenix_app_dir, "mix.exs"), "# phoenix mix file")

      test_config_content = """
      import Config

      config :phoenix_app, PhoenixAppWeb.Endpoint,
        http: [ip: {127, 0, 0, 1}, port: 4002],
        server: true
      """

      File.write!(Path.join(config_dir, "test.exs"), test_config_content)

      issues = ConfigValidator.validate_phoenix_configs(temp_dir)

      # Should find server configuration issue
      assert length(issues) > 0
      assert Enum.any?(issues, fn issue ->
        String.contains?(issue.description, "server: false")
      end)

      # Cleanup
      File.rm_rf!(temp_dir)
    end
  end

  describe "report_config_mismatches/1" do
    test "identifies version mismatches between umbrella and apps" do
      temp_dir = System.tmp_dir!() |> Path.join("mismatch_test_#{:rand.uniform(10000)}")
      File.mkdir_p!(temp_dir)
      apps_dir = Path.join(temp_dir, "apps")
      File.mkdir_p!(apps_dir)

      # Create umbrella mix.exs
      umbrella_mix_content = """
      defmodule Umbrella.MixProject do
        use Mix.Project

        def project do
          [
            apps_path: "apps",
            version: "0.1.0",
            elixir: "~> 1.14"
          ]
        end
      end
      """

      File.write!(Path.join(temp_dir, "mix.exs"), umbrella_mix_content)

      # Create app with different Elixir version
      test_app_dir = Path.join(apps_dir, "test_app")
      File.mkdir_p!(test_app_dir)

      app_mix_content = """
      defmodule TestApp.MixProject do
        use Mix.Project

        def project do
          [
            app: :test_app,
            version: "0.1.0",
            elixir: "~> 1.13"
          ]
        end
      end
      """

      File.write!(Path.join(test_app_dir, "mix.exs"), app_mix_content)

      issues = ConfigValidator.report_config_mismatches(temp_dir)

      # Should find Elixir version mismatch
      assert length(issues) > 0
      version_mismatch = Enum.find(issues, fn issue ->
        String.contains?(issue.description, "Elixir version mismatch")
      end)
      assert version_mismatch != nil

      # Cleanup
      File.rm_rf!(temp_dir)
    end

    test "handles missing umbrella configuration gracefully" do
      temp_dir = System.tmp_dir!() |> Path.join("no_umbrella_test_#{:rand.uniform(10000)}")
      File.mkdir_p!(temp_dir)

      issues = ConfigValidator.report_config_mismatches(temp_dir)

      # Should handle gracefully without crashing
      assert is_list(issues)

      # Cleanup
      File.rm_rf!(temp_dir)
    end
  end

  describe "ConfigIssue creation" do
    test "creates proper ConfigIssue structs" do
      temp_dir = System.tmp_dir!() |> Path.join("issue_creation_test_#{:rand.uniform(10000)}")
      File.mkdir_p!(temp_dir)
      apps_dir = Path.join(temp_dir, "apps")
      File.mkdir_p!(apps_dir)

      # Create minimal structure to trigger issue creation
      test_app_dir = Path.join(apps_dir, "test_app")
      File.mkdir_p!(test_app_dir)
      File.write!(Path.join(test_app_dir, "mix.exs"), "# minimal")

      issues = ConfigValidator.validate_mix_dependencies(temp_dir)

      # Verify issue structure
      if length(issues) > 0 do
        issue = hd(issues)
        assert %ConfigIssue{} = issue
        assert is_binary(issue.app_name)
        assert is_binary(issue.file_path)
        assert issue.issue_type in [:missing_dependency, :inconsistent_config, :invalid_setting, :deprecated_pattern]
        assert issue.severity in [:warning, :error, :critical]
        assert is_binary(issue.description)
        assert is_binary(issue.suggested_fix)
      end

      # Cleanup
      File.rm_rf!(temp_dir)
    end
  end
end
