defmodule TestAssessmentApp.FileDiscoveryTest do
  use ExUnit.Case, async: true

  alias TestAssessmentApp.FileDiscovery
  alias TestAssessmentApp.TestFile

  describe "discover_test_files/1" do
    test "discovers test files in current umbrella project" do
      # Use the current project as test data
      umbrella_path = File.cwd!()

      {:ok, test_files} = FileDiscovery.discover_test_files(umbrella_path)

      # Should find at least some test files
      assert length(test_files) > 0

      # All results should be TestFile structs
      assert Enum.all?(test_files, &is_struct(&1, TestFile))

      # All test files should have required fields
      Enum.each(test_files, fn test_file ->
        assert is_binary(test_file.path)
        assert is_binary(test_file.app_name)
        assert is_binary(test_file.relative_path)
        assert is_integer(test_file.size)
        assert test_file.size > 0
        assert %DateTime{} = test_file.last_modified
      end)

      # Should find test files with expected patterns
      test_file_names = Enum.map(test_files, &Path.basename(&1.path))
      assert Enum.any?(test_file_names, &String.ends_with?(&1, "_test.exs"))
    end

    test "handles non-existent directory gracefully" do
      non_existent_path = "/path/that/does/not/exist"

      {:error, reason} = FileDiscovery.discover_test_files(non_existent_path)

      assert reason != nil
    end
  end

  describe "discover_config_files/1" do
    test "discovers config files in current umbrella project" do
      umbrella_path = File.cwd!()

      {:ok, config_files} = FileDiscovery.discover_config_files(umbrella_path)

      # Should find at least some config files
      assert length(config_files) > 0

      # All config files should have required fields
      Enum.each(config_files, fn config_file ->
        assert is_binary(config_file.path)
        assert is_binary(config_file.context)
        assert is_binary(config_file.filename)
        assert is_integer(config_file.size)
        assert %DateTime{} = config_file.last_modified
      end)
    end
  end

  describe "extract_file_metadata/2" do
    test "extracts metadata from existing file" do
      # Use this test file as example
      file_path = __ENV__.file
      app_name = "test_assessment_app"

      {:ok, test_file} = FileDiscovery.extract_file_metadata(file_path, app_name)

      assert test_file.path == file_path
      assert test_file.app_name == app_name
      assert is_binary(test_file.relative_path)
      assert is_integer(test_file.size)
      assert test_file.size > 0
      assert %DateTime{} = test_file.last_modified
    end

    test "handles non-existent file gracefully" do
      file_path = "/path/to/non/existent/file.exs"
      app_name = "test_app"

      {:error, reason} = FileDiscovery.extract_file_metadata(file_path, app_name)

      assert reason != nil
    end
  end
end
