defmodule AgentCore.TestAssessment.RecommendationEngineTest do
  use ExUnit.Case, async: true

  alias AgentCore.TestAssessment.{
    RecommendationEngine,
    Recommendation,
    ParsedTest,
    RedundancyFinding,
    CoverageGap,
    ConfigIssue
  }

  describe "generate_recommendations/1" do
    test "generates recommendations from comprehensive analysis results" do
      analysis_results = %{
        redundancy_findings: [
          %RedundancyFinding{
            test_names: ["test user creation", "test create user"],
            redundancy_type: :identical_coverage,
            confidence_score: 0.95,
            recommended_action: "Remove duplicate test",
            justification: "Both tests exercise identical code paths"
          }
        ],
        coverage_gaps: [
          %CoverageGap{
            module_name: "UserService",
            function_name: "delete_user",
            gap_type: :untested_function,
            priority: :high,
            description: "Function has no test coverage",
            suggested_test_type: "unit test"
          }
        ],
        config_issues: [
          %ConfigIssue{
            app_name: "my_app",
            file_path: "config/test.exs",
            issue_type: :missing_dependency,
            severity: :error,
            description: "Missing test dependency",
            suggested_fix: "Add :mox to test dependencies"
          }
        ],
        parsed_tests: [
          %ParsedTest{
            name: "complex test",
            file_path: "test/complex_test.exs",
            line_number: 10,
            test_type: :test,
            setup_blocks: ["setup1", "setup2", "setup3", "setup4"],
            assertions: ["assert1", "assert2", "assert3", "assert4", "assert5", "assert6"],
            dependencies: [],
            complexity_score: 12.0
          }
        ]
      }

      recommendations = RecommendationEngine.generate_recommendations(analysis_results)

      assert length(recommendations) >= 4

      # Should have redundancy recommendation
      assert Enum.any?(recommendations, &(&1.type == :remove_test))

      # Should have coverage recommendation
      assert Enum.any?(recommendations, &(&1.type == :add_test))

      # Should have config recommendation
      assert Enum.any?(recommendations, &(&1.type == :update_config))

      # Should have refactoring recommendation
      assert Enum.any?(recommendations, &(&1.type == :refactor_test))
    end

    test "handles empty analysis results" do
      analysis_results = %{}
      recommendations = RecommendationEngine.generate_recommendations(analysis_results)
      assert recommendations == []
    end
  end

  describe "suggest_refactoring/1" do
    test "suggests refactoring for overly complex tests" do
      tests = [
        %ParsedTest{
          name: "complex test",
          file_path: "test/complex_test.exs",
          line_number: 10,
          test_type: :test,
          setup_blocks: [],
          assertions: [],
          dependencies: [],
          complexity_score: 15.0
        }
      ]

      recommendations = RecommendationEngine.suggest_refactoring(tests)

      assert length(recommendations) == 1
      recommendation = hd(recommendations)
      assert recommendation.type == :refactor_test
      assert recommendation.priority == :medium
      assert String.contains?(recommendation.title, "complex test")
      assert String.contains?(recommendation.description, "complexity score")
    end

    test "suggests refactoring for tests with too many assertions" do
      tests = [
        %ParsedTest{
          name: "assertion heavy test",
          file_path: "test/assertion_test.exs",
          line_number: 5,
          test_type: :test,
          setup_blocks: [],
          assertions: ["assert1", "assert2", "assert3", "assert4", "assert5", "assert6"],
          dependencies: [],
          complexity_score: 5.0
        }
      ]

      recommendations = RecommendationEngine.suggest_refactoring(tests)

      assert length(recommendations) == 1
      recommendation = hd(recommendations)
      assert recommendation.type == :refactor_test
      assert String.contains?(recommendation.description, "6 assertions")
    end

    test "suggests refactoring for tests with excessive setup" do
      tests = [
        %ParsedTest{
          name: "setup heavy test",
          file_path: "test/setup_test.exs",
          line_number: 8,
          test_type: :test,
          setup_blocks: ["setup1", "setup2", "setup3", "setup4"],
          assertions: [],
          dependencies: [],
          complexity_score: 3.0
        }
      ]

      recommendations = RecommendationEngine.suggest_refactoring(tests)

      assert length(recommendations) == 1
      recommendation = hd(recommendations)
      assert recommendation.type == :refactor_test
      assert String.contains?(recommendation.description, "4 setup blocks")
    end

    test "returns empty list for well-structured tests" do
      tests = [
        %ParsedTest{
          name: "good test",
          file_path: "test/good_test.exs",
          line_number: 5,
          test_type: :test,
          setup_blocks: ["setup1"],
          assertions: ["assert1", "assert2"],
          dependencies: [],
          complexity_score: 3.0
        }
      ]

      recommendations = RecommendationEngine.suggest_refactoring(tests)
      assert recommendations == []
    end
  end

  describe "recommend_modern_practices/1" do
    test "recommends modernization for deprecated Phoenix patterns" do
      tests = [
        %ParsedTest{
          name: "old phoenix test",
          file_path: "test/old_test.exs",
          line_number: 10,
          test_type: :test,
          setup_blocks: [],
          assertions: ["assert Phoenix.View.render(view, template)", "live_redirect(socket, to: path)"],
          dependencies: [],
          complexity_score: 2.0
        }
      ]

      recommendations = RecommendationEngine.recommend_modern_practices(tests)

      assert length(recommendations) == 1
      recommendation = hd(recommendations)
      assert recommendation.type == :modernize_pattern
      assert String.contains?(recommendation.description, "deprecated Phoenix testing patterns")
    end

    test "recommends modernization for old assertion patterns" do
      tests = [
        %ParsedTest{
          name: "old assertion test",
          file_path: "test/assertion_test.exs",
          line_number: 15,
          test_type: :test,
          setup_blocks: [],
          assertions: ["assert_receive {:ok, result}", "refute_receive {:error, _}"],
          dependencies: [],
          complexity_score: 2.0
        }
      ]

      recommendations = RecommendationEngine.recommend_modern_practices(tests)

      assert length(recommendations) == 1
      recommendation = hd(recommendations)
      assert recommendation.type == :modernize_pattern
      assert String.contains?(recommendation.description, "outdated assertion patterns")
    end

    test "returns empty list for modern tests" do
      tests = [
        %ParsedTest{
          name: "modern test",
          file_path: "test/modern_test.exs",
          line_number: 5,
          test_type: :test,
          setup_blocks: [],
          assertions: ["assert result == expected", "assert_received {:ok, _}"],
          dependencies: [],
          complexity_score: 2.0
        }
      ]

      recommendations = RecommendationEngine.recommend_modern_practices(tests)
      assert recommendations == []
    end
  end

  describe "suggest_performance_optimizations/1" do
    test "suggests optimization for high complexity tests" do
      tests = [
        %ParsedTest{
          name: "slow test",
          file_path: "test/slow_test.exs",
          line_number: 20,
          test_type: :integration,
          setup_blocks: [],
          assertions: [],
          dependencies: [],
          complexity_score: 10.0
        }
      ]

      recommendations = RecommendationEngine.suggest_performance_optimizations(tests)

      assert length(recommendations) == 1
      recommendation = hd(recommendations)
      assert recommendation.type == :refactor_test
      assert String.contains?(recommendation.description, "high complexity")
    end

    test "suggests optimization for tests with many dependencies" do
      dependencies = Enum.map(1..15, &"dependency_#{&1}")

      tests = [
        %ParsedTest{
          name: "dependency heavy test",
          file_path: "test/dependency_test.exs",
          line_number: 25,
          test_type: :test,
          setup_blocks: [],
          assertions: [],
          dependencies: dependencies,
          complexity_score: 5.0
        }
      ]

      recommendations = RecommendationEngine.suggest_performance_optimizations(tests)

      assert length(recommendations) == 1
      recommendation = hd(recommendations)
      assert recommendation.type == :refactor_test
      assert String.contains?(recommendation.description, "15 dependencies")
    end

    test "returns empty list for fast tests" do
      tests = [
        %ParsedTest{
          name: "fast test",
          file_path: "test/fast_test.exs",
          line_number: 5,
          test_type: :unit,
          setup_blocks: [],
          assertions: [],
          dependencies: ["dep1", "dep2"],
          complexity_score: 2.0
        }
      ]

      recommendations = RecommendationEngine.suggest_performance_optimizations(tests)
      assert recommendations == []
    end
  end

  describe "prioritize_action_items/1" do
    test "sorts recommendations by priority and effort" do
      recommendations = [
        %Recommendation{
          type: :refactor_test,
          priority: :low,
          title: "Low priority",
          description: "Description",
          affected_files: [],
          estimated_effort: :large,
          justification: "Justification"
        },
        %Recommendation{
          type: :add_test,
          priority: :critical,
          title: "Critical priority",
          description: "Description",
          affected_files: [],
          estimated_effort: :small,
          justification: "Justification"
        },
        %Recommendation{
          type: :update_config,
          priority: :high,
          title: "High priority",
          description: "Description",
          affected_files: [],
          estimated_effort: :medium,
          justification: "Justification"
        }
      ]

      sorted = RecommendationEngine.prioritize_action_items(recommendations)

      # Critical priority with small effort should be first
      assert hd(sorted).priority == :critical
      assert hd(sorted).estimated_effort == :small

      # High priority should be second
      assert Enum.at(sorted, 1).priority == :high

      # Low priority should be last
      assert List.last(sorted).priority == :low
    end

    test "handles empty recommendation list" do
      recommendations = []
      sorted = RecommendationEngine.prioritize_action_items(recommendations)
      assert sorted == []
    end
  end
end
