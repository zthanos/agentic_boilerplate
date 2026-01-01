defmodule AgentCore.TestAssessment.CategorizationTest do
  use ExUnit.Case, async: true

  alias AgentCore.TestAssessment.{Categorization, ParsedTest, TestCategory}

  describe "categorize_test/1" do
    test "categorizes unit tests correctly" do
      parsed_test = %ParsedTest{
        name: "test user validation",
        file_path: "/test/user_test.exs",
        line_number: 10,
        test_type: :test,
        setup_blocks: ["setup do"],
        assertions: ["assert user.valid?", "refute user.errors"],
        dependencies: ["ExUnit.Case"],
        complexity_score: 2.0
      }

      category = Categorization.categorize_test(parsed_test)

      assert category.primary_type == :unit
      assert category.confidence_scores.unit > 0.5
      assert "validation" in category.focus_areas
    end

    test "categorizes integration tests correctly" do
      parsed_test = %ParsedTest{
        name: "test user creation via API",
        file_path: "/test/integration/user_api_test.exs",
        line_number: 15,
        test_type: :test,
        setup_blocks: ["setup %{conn: conn}"],
        assertions: ["assert response.status == 200"],
        dependencies: ["Phoenix.ConnTest", "Ecto.Repo"],
        complexity_score: 4.0
      }

      category = Categorization.categorize_test(parsed_test)

      assert category.primary_type == :integration
      assert category.confidence_scores.integration > 0.5
      assert "api" in category.focus_areas
    end

    test "categorizes property-based tests correctly" do
      parsed_test = %ParsedTest{
        name: "property test for user validation",
        file_path: "/test/property/user_property_test.exs",
        line_number: 20,
        test_type: :property,
        setup_blocks: [],
        assertions: ["check all user <- user_generator()"],
        dependencies: ["StreamData"],
        complexity_score: 3.0
      }

      category = Categorization.categorize_test(parsed_test)

      assert category.primary_type == :property_based
      assert category.confidence_scores.property_based > 0.5
    end

    test "categorizes end-to-end tests correctly" do
      parsed_test = %ParsedTest{
        name: "test complete user workflow",
        file_path: "/test/e2e/user_workflow_test.exs",
        line_number: 25,
        test_type: :test,
        setup_blocks: ["setup %{conn: conn}"],
        assertions: ["render_submit(view, :save)", "assert has_element?(view, \"#success\")"],
        dependencies: ["Phoenix.LiveViewTest"],
        complexity_score: 6.0
      }

      category = Categorization.categorize_test(parsed_test)

      assert category.primary_type == :end_to_end
      assert category.confidence_scores.end_to_end > 0.5
      assert "ui" in category.focus_areas
    end

    test "handles ambiguous tests with multiple categories" do
      parsed_test = %ParsedTest{
        name: "test user API with database integration",
        file_path: "/test/user_api_integration_test.exs",
        line_number: 30,
        test_type: :test,
        setup_blocks: ["setup %{conn: conn}"],
        assertions: ["assert user.valid?", "post conn, \"/api/users\""],
        dependencies: ["Phoenix.ConnTest", "Ecto.Repo", "ExUnit.Case"],
        complexity_score: 5.0
      }

      category = Categorization.categorize_test(parsed_test)

      # Should have multiple secondary types due to mixed patterns
      assert length(category.secondary_types) > 0
      assert "api" in category.focus_areas
      assert "database" in category.focus_areas
    end
  end

  describe "assign_confidence_score/1" do
    test "normalizes confidence scores to sum to 1.0" do
      category = %TestCategory{
        primary_type: :unit,
        secondary_types: [],
        confidence_scores: %{unit: 2.0, integration: 1.0, property_based: 0.0, end_to_end: 1.0},
        focus_areas: []
      }

      normalized = Categorization.assign_confidence_score(category)

      total = normalized.confidence_scores |> Map.values() |> Enum.sum()
      assert_in_delta total, 1.0, 0.01
    end

    test "handles zero confidence scores" do
      category = %TestCategory{
        primary_type: :unit,
        secondary_types: [],
        confidence_scores: %{unit: 0.0, integration: 0.0, property_based: 0.0, end_to_end: 0.0},
        focus_areas: []
      }

      normalized = Categorization.assign_confidence_score(category)

      assert normalized.confidence_scores.unit == 1.0
      assert normalized.confidence_scores.integration == 0.0
    end
  end

  describe "group_similar_tests/1" do
    test "groups tests by similar patterns" do
      tests = [
        %ParsedTest{
          name: "test user validation 1",
          file_path: "/test/user_test.exs",
          line_number: 10,
          test_type: :test,
          setup_blocks: [],
          assertions: ["assert user.valid?"],
          dependencies: [],
          complexity_score: 2.0
        },
        %ParsedTest{
          name: "test user validation 2",
          file_path: "/test/user_test.exs",
          line_number: 20,
          test_type: :test,
          setup_blocks: [],
          assertions: ["assert user.valid?"],
          dependencies: [],
          complexity_score: 2.0
        },
        %ParsedTest{
          name: "property test for user",
          file_path: "/test/user_property_test.exs",
          line_number: 30,
          test_type: :property,
          setup_blocks: [],
          assertions: ["check all user <- user_generator()"],
          dependencies: ["StreamData"],
          complexity_score: 3.0
        }
      ]

      groups = Categorization.group_similar_tests(tests)

      assert map_size(groups) >= 2

      # Should have groups with meaningful names and counts
      group_names = Map.keys(groups)
      assert Enum.any?(group_names, &String.contains?(&1, "Property-based"))
      assert Enum.any?(group_names, &String.contains?(&1, "("))
    end

    test "handles empty test list" do
      groups = Categorization.group_similar_tests([])
      assert groups == %{}
    end

    test "groups complex tests separately" do
      complex_test = %ParsedTest{
        name: "test complex user workflow",
        file_path: "/test/user_test.exs",
        line_number: 10,
        test_type: :test,
        setup_blocks: ["setup1", "setup2", "setup3"],
        assertions: ["assert1", "assert2", "assert3", "assert4", "assert5", "assert6"],
        dependencies: [],
        complexity_score: 8.0
      }

      simple_test = %ParsedTest{
        name: "test simple validation",
        file_path: "/test/user_test.exs",
        line_number: 20,
        test_type: :test,
        setup_blocks: [],
        assertions: ["assert user.valid?"],
        dependencies: [],
        complexity_score: 1.0
      }

      groups = Categorization.group_similar_tests([complex_test, simple_test])

      # Complex and simple tests should be in different groups
      assert map_size(groups) == 2

      complex_group = groups |> Enum.find(fn {name, _} -> String.contains?(name, "Complex") end)
      assert complex_group != nil
    end
  end
end
