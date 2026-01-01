defmodule AgentCore.TestAssessment.PhoenixAnalysisTest do
  use ExUnit.Case, async: true

  alias AgentCore.TestAssessment.{PhoenixAnalysis, ParsedTest}

  describe "analyze_liveview_interactions/1" do
    test "identifies LiveView tests and interactions" do
      liveview_test = %ParsedTest{
        name: "test LiveView interaction",
        file_path: "/test/live/user_live_test.exs",
        line_number: 10,
        test_type: :test,
        setup_blocks: ["use Phoenix.LiveViewTest"],
        assertions: ["render_click(view, \"save\")", "has_element?(view, \"#form\")"],
        dependencies: ["Phoenix.LiveViewTest"],
        complexity_score: 3.0
      }

      regular_test = %ParsedTest{
        name: "test regular function",
        file_path: "/test/user_test.exs",
        line_number: 5,
        test_type: :test,
        setup_blocks: [],
        assertions: ["assert user.name == \"John\""],
        dependencies: [],
        complexity_score: 1.0
      }

      result = PhoenixAnalysis.analyze_liveview_interactions([liveview_test, regular_test])

      assert is_map(result)
      assert Map.has_key?(result, :tested_interactions)
      assert Map.has_key?(result, :untested_interactions)
      assert Map.has_key?(result, :interaction_coverage)
      assert Map.has_key?(result, :recommendations)

      assert is_list(result.tested_interactions)
      assert is_list(result.untested_interactions)
      assert is_number(result.interaction_coverage)
      assert is_list(result.recommendations)
    end

    test "handles empty test list" do
      result = PhoenixAnalysis.analyze_liveview_interactions([])

      assert result.tested_interactions == []
      assert result.untested_interactions == []
      assert result.interaction_coverage == 100.0
      assert result.recommendations == []
    end
  end

  describe "detect_form_validation_coverage/1" do
    test "identifies form validation patterns" do
      validation_test = %ParsedTest{
        name: "test user validation",
        file_path: "/test/user_test.exs",
        line_number: 15,
        test_type: :test,
        setup_blocks: [],
        assertions: ["validate_required(changeset, [:name])", "validate_length(changeset, :name, min: 2)"],
        dependencies: ["Ecto.Changeset"],
        complexity_score: 2.0
      }

      result = PhoenixAnalysis.detect_form_validation_coverage([validation_test])

      assert is_map(result)
      assert Map.has_key?(result, :tested_validations)
      assert Map.has_key?(result, :untested_validations)
      assert Map.has_key?(result, :validation_coverage)
      assert Map.has_key?(result, :coverage_gaps)

      assert is_list(result.tested_validations)
      assert is_list(result.untested_validations)
      assert is_number(result.validation_coverage)
      assert is_list(result.coverage_gaps)
    end
  end

  describe "identify_untested_component_interactions/1" do
    test "identifies Phoenix component patterns" do
      component_test = %ParsedTest{
        name: "test user component",
        file_path: "/test/components/user_component_test.exs",
        line_number: 8,
        test_type: :test,
        setup_blocks: ["use Phoenix.Component"],
        assertions: ["render_component(&user_card/1, %{user: user})", "has_element?(html, \".user-card\")"],
        dependencies: ["Phoenix.Component"],
        complexity_score: 2.5
      }

      result = PhoenixAnalysis.identify_untested_component_interactions([component_test])

      assert is_map(result)
      assert Map.has_key?(result, :tested_components)
      assert Map.has_key?(result, :untested_components)
      assert Map.has_key?(result, :component_coverage)
      assert Map.has_key?(result, :coverage_gaps)

      assert is_list(result.tested_components)
      assert is_list(result.untested_components)
      assert is_number(result.component_coverage)
      assert is_list(result.coverage_gaps)
    end
  end

  describe "detect_property_test_opportunities/1" do
    test "identifies parser and transformation opportunities" do
      parser_test = %ParsedTest{
        name: "test JSON parser",
        file_path: "/test/parser_test.exs",
        line_number: 12,
        test_type: :test,
        setup_blocks: [],
        assertions: ["Jason.decode(json_string)", "parse_user_data(data)"],
        dependencies: ["Jason"],
        complexity_score: 3.5
      }

      property_test = %ParsedTest{
        name: "property test for transformation",
        file_path: "/test/transform_property_test.exs",
        line_number: 5,
        test_type: :test,
        setup_blocks: ["use StreamData"],
        assertions: ["check all data <- user_data_generator()"],
        dependencies: ["StreamData"],
        complexity_score: 4.0
      }

      result = PhoenixAnalysis.detect_property_test_opportunities([parser_test, property_test])

      assert is_map(result)
      assert Map.has_key?(result, :parser_opportunities)
      assert Map.has_key?(result, :transformation_opportunities)
      assert Map.has_key?(result, :existing_property_tests)
      assert Map.has_key?(result, :recommendations)

      assert is_list(result.parser_opportunities)
      assert is_list(result.transformation_opportunities)
      assert is_list(result.existing_property_tests)
      assert is_list(result.recommendations)

      # Should identify the property test
      assert length(result.existing_property_tests) > 0
    end
  end

  describe "analyze_phoenix_features/1" do
    test "performs comprehensive Phoenix analysis" do
      mixed_tests = [
        %ParsedTest{
          name: "test LiveView interaction",
          file_path: "/test/live/user_live_test.exs",
          line_number: 10,
          test_type: :test,
          setup_blocks: ["use Phoenix.LiveViewTest"],
          assertions: ["render_click(view, \"save\")", "validate_required(changeset, [:name])"],
          dependencies: ["Phoenix.LiveViewTest"],
          complexity_score: 3.0
        },
        %ParsedTest{
          name: "test component rendering",
          file_path: "/test/components/card_test.exs",
          line_number: 5,
          test_type: :test,
          setup_blocks: ["use Phoenix.Component"],
          assertions: ["render_component(&card/1, %{title: \"Test\"})"],
          dependencies: ["Phoenix.Component"],
          complexity_score: 2.0
        }
      ]

      result = PhoenixAnalysis.analyze_phoenix_features(mixed_tests)

      assert is_map(result)
      assert Map.has_key?(result, :liveview_analysis)
      assert Map.has_key?(result, :form_validation_analysis)
      assert Map.has_key?(result, :component_analysis)
      assert Map.has_key?(result, :property_test_analysis)
      assert Map.has_key?(result, :overall_phoenix_coverage)
      assert Map.has_key?(result, :phoenix_recommendations)

      assert is_number(result.overall_phoenix_coverage)
      assert result.overall_phoenix_coverage >= 0.0
      assert result.overall_phoenix_coverage <= 100.0
      assert is_list(result.phoenix_recommendations)
    end

    test "handles empty test list gracefully" do
      result = PhoenixAnalysis.analyze_phoenix_features([])

      assert is_map(result)
      assert result.overall_phoenix_coverage >= 0.0
      assert is_list(result.phoenix_recommendations)
    end
  end
end
