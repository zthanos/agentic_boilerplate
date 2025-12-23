defmodule AgentRuntime.Flows.Requirements.Schema do
  @moduledoc false

  def schema do
    %{
      "$schema" => "http://json-schema.org/draft-07/schema#",
      "$id" => "https://agent_runtime/schemas/requirements.json",
      "title" => "RequirementsExtraction",
      "type" => "object",
      "additionalProperties" => false,
      "required" => [
        "meta",
        "actors",
        "systems",
        "functional_requirements",
        "non_functional_requirements",
        "assumptions",
        "open_questions"
      ],
      "properties" => %{
        "meta" => %{
          "type" => "object",
          "additionalProperties" => false,
          "required" => ["version", "language", "confidence"],
          "properties" => %{
            "version" => %{"type" => "string", "minLength" => 1},
            "language" => %{"type" => "string", "enum" => ["en", "el"]},
            "confidence" => %{"type" => "number", "minimum" => 0.0, "maximum" => 1.0}
          }
        },
        "actors" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "additionalProperties" => false,
            "required" => ["id", "name", "type"],
            "properties" => %{
              "id" => %{"type" => "string", "pattern" => "^[a-z0-9_\\-]+$"},
              "name" => %{"type" => "string", "minLength" => 1},
              "type" => %{"type" => "string", "enum" => ["user", "admin", "system", "external_party"]},
              "description" => %{"type" => "string"}
            }
          }
        },
        "systems" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "additionalProperties" => false,
            "required" => ["id", "name", "role"],
            "properties" => %{
              "id" => %{"type" => "string", "pattern" => "^[a-z0-9_\\-]+$"},
              "name" => %{"type" => "string", "minLength" => 1},
              "role" => %{"type" => "string", "enum" => ["primary", "supporting", "external"]},
              "description" => %{"type" => "string"}
            }
          }
        },
        "functional_requirements" => %{
          "type" => "array",
          "items" => requirement_item_schema("FR")
        },
        "non_functional_requirements" => %{
          "type" => "array",
          "items" => nfr_item_schema()
        },
        "assumptions" => %{"type" => "array", "items" => %{"type" => "string", "minLength" => 1}},
        "open_questions" => %{"type" => "array", "items" => %{"type" => "string", "minLength" => 1}}
      }
    }
  end

  defp requirement_item_schema(prefix) do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["id", "title", "description", "priority", "status"],
      "properties" => %{
        "id" => %{"type" => "string", "pattern" => "^#{prefix}-\\d{3,}$"},
        "title" => %{"type" => "string", "minLength" => 1},
        "description" => %{"type" => "string", "minLength" => 1},
        "priority" => %{"type" => "string", "enum" => ["must", "should", "could", "wont"]},
        "status" => %{"type" => "string", "enum" => ["proposed", "confirmed"]},
        "actors" => %{"type" => "array", "items" => %{"type" => "string", "pattern" => "^[a-z0-9_\\-]+$"}},
        "systems" => %{"type" => "array", "items" => %{"type" => "string", "pattern" => "^[a-z0-9_\\-]+$"}},
        "acceptance_criteria" => %{"type" => "array", "items" => %{"type" => "string", "minLength" => 1}},
        "references" => %{"type" => "array", "items" => %{"type" => "string", "minLength" => 1}}
      }
    }
  end

  defp nfr_item_schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["id", "category", "description", "priority", "status"],
      "properties" => %{
        "id" => %{"type" => "string", "pattern" => "^NFR-\\d{3,}$"},
        "category" => %{
          "type" => "string",
          "enum" => [
            "security",
            "availability",
            "performance",
            "scalability",
            "observability",
            "compliance",
            "usability",
            "maintainability",
            "data",
            "operational"
          ]
        },
        "description" => %{"type" => "string", "minLength" => 1},
        "priority" => %{"type" => "string", "enum" => ["must", "should", "could", "wont"]},
        "status" => %{"type" => "string", "enum" => ["proposed", "confirmed"]},
        "measurement" => %{"type" => "string"},
        "references" => %{"type" => "array", "items" => %{"type" => "string", "minLength" => 1}}
      }
    }
  end
end
