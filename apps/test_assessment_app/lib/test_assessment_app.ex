defmodule TestAssessmentApp do
  @moduledoc """
  TestAssessmentApp provides comprehensive test suite analysis and optimization
  capabilities for Phoenix umbrella projects.

  This module serves as the main entry point for test assessment functionality,
  offering tools to analyze test coverage, detect redundancies, generate
  recommendations, and optimize test suites.
  """

  @doc """
  Assess a test suite for the given umbrella project path.

  ## Parameters
  - `umbrella_path`: Path to the umbrella project root
  - `opts`: Optional configuration (progress_callback, etc.)

  ## Returns
  - `{:ok, AssessmentReport.t()}` on success
  - `{:error, term()}` on failure
  """
  defdelegate assess_test_suite(umbrella_path, opts \\ []), to: TestAssessmentApp.Core

  @doc """
  Validate that the given path is a valid umbrella project.

  ## Parameters
  - `path`: Path to validate

  ## Returns
  - `{:ok, [app_paths]}` if valid umbrella project
  - `{:error, reason}` if invalid
  """
  defdelegate validate_umbrella_project(path), to: TestAssessmentApp.Core
end
