defmodule AgentCore.TestAssessment.RedundancyDetectorTest do
  use ExUnit.Case, async: true

  alias AgentCore.TestAssessment.{
    RedundancyDetector,
    ParsedTest,
    RedundancyFinding,
    CoverageReport
  }

  describe "detect_redundant_coverage/2" do
    test "identifies tests with identical coverage patterns" do
      coverage_report = %CoverageReport{
        total_lines: 100,
        covered_lines: 80,
        coverage_percentage: 80.0,
        uncovered_functions: [],
        test_coverage_map: %{
          "test_user_creation" => ["UserController.create", "User.changeset"],
          "test_user_creation_duplicate" => ["UserController.create", "User.changeset"],
          "test_user_update" => ["UserController.update", "User.changeset"]
        }
      }

      parsed_tests = [
        %ParsedTest{
          name: "test_user_creation",
          file_path: "test/user_test.exs",
          line_number: 10,
          test_type: :test,
          setup_blocks: ["setup_user"],
          assertions: ["assert user.name == \"John\""],
          dependencies: ["User"],
          complexity_score: 2.0
        },
        %ParsedTest{
          name: "test_user_creation_duplicate",
          file_path: "test/user_test.exs",
          line_number: 20,
          test_type: :test,
          setup_blocks: ["setup_user"],
          assertions: ["assert user.name == \"Jane\""],
          dependencies: ["User"],
          complexity_score: 1.5
        },
        %ParsedTest{
          name: "test_user_update",
          file_path: "test/user_test.exs",
          line_number: 30,
          test_type: :test,
          setup_blocks: ["setup_user"],
          assertions: ["assert user.updated_at"],
          dependencies: ["User"],
          complexity_score: 2.5
        }
      ]

      findings = RedundancyDetector.detect_redundant_coverage(parsed_tests, coverage_report)

      assert length(findings) == 1
      finding = List.first(findings)
      assert finding.redundancy_type == :identical_coverage
      assert "test_user_creation" in finding.test_names
      assert "test_user_creation_duplicate" in finding.test_names
      assert finding.confidence_score > 0.7
      assert String.contains?(finding.recommended_action, "test_user_creation")
    end

    test "returns empty list when no redundant coverage found" do
      coverage_report = %CoverageReport{
        total_lines: 100,
        covered_lines: 80,
        coverage_percentage: 80.0,
        uncovered_functions: [],
        test_coverage_map: %{
          "test_user_creation" => ["UserController.create"],
          "test_user_update" => ["UserController.update"]
        }
      }

      parsed_tests = [
        %ParsedTest{
          name: "test_user_creation",
          file_path: "test/user_test.exs",
          line_number: 10,
          test_type: :test,
          setup_blocks: [],
          assertions: ["assert user.name"],
          dependencies: [],
          complexity_score: 1.0
        },
        %ParsedTest{
          name: "test_user_update",
          file_path: "test/user_test.exs",
          line_number: 20,
          test_type: :test,
          setup_blocks: [],
          assertions: ["assert user.updated_at"],
          dependencies: [],
          complexity_score: 1.0
        }
      ]

      findings = RedundancyDetector.detect_redundant_coverage(parsed_tests, coverage_report)

      assert findings == []
    end
  end

  describe "detect_similar_logic/1" do
    test "identifies tests with similar assertion patterns" do
      parsed_tests = [
        %ParsedTest{
          name: "test_user_validation_name",
          file_path: "test/user_test.exs",
          line_number: 10,
          test_type: :test,
          setup_blocks: [],
          assertions: ["assert changeset.valid? == false", "assert errors_on(changeset).name"],
          dependencies: [],
          complexity_score: 2.0
        },
        %ParsedTest{
          name: "test_user_validation_email",
          file_path: "test/user_test.exs",
          line_number: 20,
          test_type: :test,
          setup_blocks: [],
          assertions: ["assert changeset.valid? == false", "assert errors_on(changeset).email"],
          dependencies: [],
          complexity_score: 1.8
        },
        %ParsedTest{
          name: "test_user_creation_success",
          file_path: "test/user_test.exs",
          line_number: 30,
          test_type: :test,
          setup_blocks: [],
          assertions: ["assert changeset.valid? == true"],
          dependencies: [],
          complexity_score: 1.0
        }
      ]

      findings = RedundancyDetector.detect_similar_logic(parsed_tests)

      assert length(findings) == 1
      finding = List.first(findings)
      assert finding.redundancy_type == :similar_logic
      assert "test_user_validation_name" in finding.test_names
      assert "test_user_validation_email" in finding.test_names
      assert finding.confidence_score > 0.4
      assert String.contains?(finding.recommended_action, "test_user_validation_name")
    end

    test "returns empty list when no similar logic found" do
      parsed_tests = [
        %ParsedTest{
          name: "test_user_creation",
          file_path: "test/user_test.exs",
          line_number: 10,
          test_type: :test,
          setup_blocks: [],
          assertions: ["assert user.name"],
          dependencies: [],
          complexity_score: 1.0
        },
        %ParsedTest{
          name: "test_user_deletion",
          file_path: "test/user_test.exs",
          line_number: 20,
          test_type: :test,
          setup_blocks: [],
          assertions: ["refute Repo.get(User, user.id)"],
          dependencies: [],
          complexity_score: 1.0
        }
      ]

      findings = RedundancyDetector.detect_similar_logic(parsed_tests)

      assert findings == []
    end
  end

  describe "recommend_tests_to_keep/1" do
    test "recommends test with highest quality score" do
      tests = [
        %ParsedTest{
          name: "simple_test",
          file_path: "test/user_test.exs",
          line_number: 10,
          test_type: :test,
          setup_blocks: [],
          assertions: ["assert true"],
          dependencies: [],
          complexity_score: 1.0
        },
        %ParsedTest{
          name: "comprehensive_test",
          file_path: "test/user_test.exs",
          line_number: 20,
          test_type: :test,
          setup_blocks: ["setup_user", "setup_context"],
          assertions: ["assert user.name", "assert user.email", "assert user.valid?"],
          dependencies: ["User"],
          complexity_score: 3.0
        }
      ]

      recommended = RedundancyDetector.recommend_tests_to_keep(tests)

      assert recommended == ["comprehensive_test"]
    end

    test "returns empty list for empty input" do
      recommended = RedundancyDetector.recommend_tests_to_keep([])

      assert recommended == []
    end
  end

  describe "handle_liveview_redundancy/1" do
    test "identifies redundant LiveView tests with identical interaction patterns" do
      liveview_tests = [
        %ParsedTest{
          name: "test_button_click_user_creation",
          file_path: "test/user_live_test.exs",
          line_number: 10,
          test_type: :test,
          setup_blocks: [],
          assertions: [
            "render_click(view, \"create-user\")",
            "assert has_element(view, \"#user-form\")"
          ],
          dependencies: ["Phoenix.LiveViewTest"],
          complexity_score: 2.0
        },
        %ParsedTest{
          name: "test_button_click_duplicate",
          file_path: "test/user_live_test.exs",
          line_number: 20,
          test_type: :test,
          setup_blocks: [],
          assertions: [
            "render_click(view, \"create-user\")",
            "assert has_element(view, \"#user-form\")"
          ],
          dependencies: ["Phoenix.LiveViewTest"],
          complexity_score: 1.8
        },
        %ParsedTest{
          name: "test_form_submit",
          file_path: "test/user_live_test.exs",
          line_number: 30,
          test_type: :test,
          setup_blocks: [],
          assertions: ["render_submit(view, \"user-form\", %{user: %{name: \"John\"}})"],
          dependencies: ["Phoenix.LiveViewTest"],
          complexity_score: 2.5
        }
      ]

      findings = RedundancyDetector.handle_liveview_redundancy(liveview_tests)

      assert length(findings) == 1
      finding = List.first(findings)
      assert finding.redundancy_type == :duplicate_assertions
      assert "test_button_click_user_creation" in finding.test_names
      assert "test_button_click_duplicate" in finding.test_names
      assert finding.confidence_score == 0.8
    end

    test "does not flag LiveView tests with different interaction patterns" do
      liveview_tests = [
        %ParsedTest{
          name: "test_button_click",
          file_path: "test/user_live_test.exs",
          line_number: 10,
          test_type: :test,
          setup_blocks: [],
          assertions: ["render_click(view, \"create-user\")"],
          dependencies: ["Phoenix.LiveViewTest"],
          complexity_score: 1.0
        },
        %ParsedTest{
          name: "test_form_submit",
          file_path: "test/user_live_test.exs",
          line_number: 20,
          test_type: :test,
          setup_blocks: [],
          assertions: ["render_submit(view, \"user-form\", %{})"],
          dependencies: ["Phoenix.LiveViewTest"],
          complexity_score: 1.0
        }
      ]

      findings = RedundancyDetector.handle_liveview_redundancy(liveview_tests)

      assert findings == []
    end

    test "filters out non-LiveView tests" do
      mixed_tests = [
        %ParsedTest{
          name: "test_regular_function",
          file_path: "test/user_test.exs",
          line_number: 10,
          test_type: :test,
          setup_blocks: [],
          assertions: ["assert User.create(%{name: \"John\"})"],
          dependencies: [],
          complexity_score: 1.0
        },
        %ParsedTest{
          name: "test_liveview_interaction",
          file_path: "test/user_live_test.exs",
          line_number: 20,
          test_type: :test,
          setup_blocks: [],
          assertions: ["render_click(view, \"button\")"],
          dependencies: ["Phoenix.LiveViewTest"],
          complexity_score: 1.0
        }
      ]

      findings = RedundancyDetector.handle_liveview_redundancy(mixed_tests)

      # Should not find any redundancy since there's only one LiveView test
      assert findings == []
    end
  end
end
