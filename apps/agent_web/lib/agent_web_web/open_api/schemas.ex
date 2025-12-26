defmodule AgentWeb.OpenApi.Schemas do
  @moduledoc false
  alias OpenApiSpex.Schema

  defmodule ChatMessage do
    require OpenApiSpex
    OpenApiSpex.schema(%{
      title: "ChatMessage",
      type: :object,
      required: [:role, :content],
      additionalProperties: false,
      properties: %{
        role: %Schema{type: :string, enum: ["user", "assistant", "system", "tool"]},
        content: %Schema{type: :string}
      }
    })
  end

  defmodule LlmInputChat do
    require OpenApiSpex
    OpenApiSpex.schema(%{
      title: "LlmInputChat",
      type: :object,
      required: [:type, :messages],
      additionalProperties: false,
      properties: %{
        type: %Schema{type: :string, enum: ["chat"]},
        messages: %Schema{
          type: :array,
          minItems: 1,
          items: ChatMessage
        }
      }
    })
  end

  defmodule LlmExecuteRequest do
    require OpenApiSpex
    OpenApiSpex.schema(%{
      title: "LlmExecuteRequest",
      type: :object,
      required: [:profile_id, :input],
      additionalProperties: false,
      properties: %{
        profile_id: %Schema{type: :string, minLength: 1},
        input: LlmInputChat,
        overrides: %Schema{type: :object, nullable: true, additionalProperties: true},
        trace_id: %Schema{type: :string, nullable: true},
        parent_run_id: %Schema{type: :string, nullable: true},
        phase: %Schema{type: :string, nullable: true, enum: ["draft", "critique", "revise", "final"]}
      }
    })
  end

  defmodule Usage do
    require OpenApiSpex
    OpenApiSpex.schema(%{
      title: "Usage",
      type: :object,
      additionalProperties: true,
      properties: %{
        prompt_tokens: %Schema{type: :integer, nullable: true},
        completion_tokens: %Schema{type: :integer, nullable: true},
        total_tokens: %Schema{type: :integer, nullable: true}
      }
    })
  end

  defmodule LlmExecuteResponseOk do
    require OpenApiSpex
    OpenApiSpex.schema(%{
      title: "LlmExecuteResponseOk",
      type: :object,
      required: [:status, :run_id, :trace_id, :fingerprint],
      additionalProperties: false,
      properties: %{
        status: %Schema{type: :string, enum: ["ok"]},
        run_id: %Schema{type: :string},
        trace_id: %Schema{type: :string},
        fingerprint: %Schema{type: :string},
        latency_ms: %Schema{type: :integer, nullable: true},
        output_text: %Schema{type: :string, nullable: true},
        output: %Schema{type: :object, nullable: true, additionalProperties: true},
        usage: Usage
      }
    })
  end

  defmodule LlmExecuteResponseError do
    require OpenApiSpex
    OpenApiSpex.schema(%{
      title: "LlmExecuteResponseError",
      type: :object,
      required: [:status, :error],
      additionalProperties: false,
      properties: %{
        status: %Schema{type: :string, enum: ["error"]},
        run_id: %Schema{type: :string, nullable: true},
        trace_id: %Schema{type: :string, nullable: true},
        fingerprint: %Schema{type: :string, nullable: true},
        latency_ms: %Schema{type: :integer, nullable: true},
        error: %Schema{type: :object, additionalProperties: true},
        details: %Schema{type: :string, nullable: true}
      }
    })
  end

  defmodule RunSnapshot do
    require OpenApiSpex
    OpenApiSpex.schema(%{
      title: "RunSnapshot",
      type: :object,
      required: [
        :run_id,
        :trace_id,
        :fingerprint,
        :profile_id,
        :provider,
        :model,
        :policy_version,
        :resolved_at,
        :invocation_config
      ],
      additionalProperties: false,
      properties: %{
        run_id: %Schema{type: :string},
        trace_id: %Schema{type: :string},
        parent_run_id: %Schema{type: :string, nullable: true},
        phase: %Schema{type: :string, nullable: true},
        fingerprint: %Schema{type: :string},
        profile_id: %Schema{type: :string},
        profile_name: %Schema{type: :string, nullable: true},
        provider: %Schema{type: :string},
        model: %Schema{type: :string},
        policy_version: %Schema{type: :string},
        resolved_at: %Schema{type: :string, format: "date-time"},
        overrides: %Schema{type: :object, nullable: true, additionalProperties: true},
        invocation_config: %Schema{type: :object, additionalProperties: true}
      }
    })
  end

  defmodule RunsIndexResponse do
    require OpenApiSpex
    OpenApiSpex.schema(%{
      title: "RunsIndexResponse",
      type: :object,
      required: [:data, :meta],
      additionalProperties: false,
      properties: %{
        data: %Schema{type: :array, items: RunSnapshot},
        meta: %Schema{
          type: :object,
          required: [:limit, :count],
          additionalProperties: false,
          properties: %{
            limit: %Schema{type: :integer},
            count: %Schema{type: :integer}
          }
        }
      }
    })
  end

  defmodule RunShowResponse do
    require OpenApiSpex
    OpenApiSpex.schema(%{
      title: "RunShowResponse",
      type: :object,
      required: [:data],
      additionalProperties: false,
      properties: %{
        data: RunSnapshot
      }
    })
  end

  defmodule ApiError do
    require OpenApiSpex
    OpenApiSpex.schema(%{
      title: "ApiError",
      type: :object,
      required: [:status, :error],
      additionalProperties: false,
      properties: %{
        status: %Schema{type: :string, enum: ["error"]},
        error: %Schema{type: :object, additionalProperties: true}
      }
    })
  end
end
