defmodule AgentRuntime.Flows.Requirements.ParserTest do
  use ExUnit.Case, async: true

  alias AgentRuntime.Flows.Requirements.Parser

  test "valid json passes schema validation" do
    json = %{
      "meta" => %{"version" => "1.0", "language" => "en", "confidence" => 0.8},
      "actors" => [%{"id" => "end_user", "name" => "End User", "type" => "user"}],
      "systems" => [%{"id" => "portal", "name" => "Customer Portal", "role" => "primary"}],
      "functional_requirements" => [
        %{
          "id" => "FR-001",
          "title" => "User login",
          "description" => "The user can log in with username and password.",
          "priority" => "must",
          "status" => "proposed",
          "actors" => ["end_user"],
          "systems" => ["portal"],
          "acceptance_criteria" => ["Given valid credentials, when login, then access is granted."]
        }
      ],
      "non_functional_requirements" => [
        %{
          "id" => "NFR-001",
          "category" => "security",
          "description" => "Passwords must be stored hashed using a modern algorithm.",
          "priority" => "must",
          "status" => "proposed",
          "measurement" => "OWASP ASVS aligned"
        }
      ],
      "assumptions" => ["Users already have registered accounts."],
      "open_questions" => ["Do we require MFA for all users?"]
    }

    text = Jason.encode!(json)
    assert {:ok, _} = Parser.parse_and_validate(text)
  end

  test "invalid json is rejected" do
    assert {:error, {:invalid_json, _}} = Parser.parse_and_validate("{not json")
  end

  test "schema mismatch is rejected" do
    # Missing required keys
    bad = %{"meta" => %{"version" => "1.0", "language" => "en", "confidence" => 0.5}}
    assert {:error, {:schema_mismatch, _errors}} = Parser.parse_and_validate(Jason.encode!(bad))
  end

  test "additional properties are rejected" do
    bad =
      %{
        "meta" => %{"version" => "1.0", "language" => "en", "confidence" => 0.5, "extra" => "nope"},
        "actors" => [],
        "systems" => [],
        "functional_requirements" => [],
        "non_functional_requirements" => [],
        "assumptions" => [],
        "open_questions" => []
      }

    assert {:error, {:schema_mismatch, _}} = Parser.parse_and_validate(Jason.encode!(bad))
  end
end
