defmodule AgentRuntime.TestSupport.JsonProvider do
  @moduledoc false

  alias AgentCore.Llm.ProviderRequest
  alias AgentCore.Llm.ProviderResponse

  @spec call(ProviderRequest.t()) :: {:ok, ProviderResponse.t()} | {:error, term()}
  def call(%ProviderRequest{} = req) do
    prompt =
      case req.input do
        %{type: :completion, prompt: p} when is_binary(p) -> p
        _ -> ""
      end

    json = %{
      "meta" => %{"version" => "1.0", "language" => "en", "confidence" => 0.8},
      "actors" => [%{"id" => "end_user", "name" => "End User", "type" => "user"}],
      "systems" => [%{"id" => "portal", "name" => "Customer Portal", "role" => "primary"}],
      "functional_requirements" => [
        %{
          "id" => "FR-001",
          "title" => "Authentication",
          "description" => "Users can authenticate to access the system. Source: #{prompt}",
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
          "description" => "Credentials must be handled securely.",
          "priority" => "must",
          "status" => "proposed",
          "measurement" => "OWASP ASVS aligned"
        }
      ],
      "assumptions" => [],
      "open_questions" => ["Is MFA required for all users?"]
    }

    {:ok,
     %ProviderResponse{
       output_text: Jason.encode!(json),
       raw: %{"provider" => "test_json"},
       usage: %{}
     }}
  end
end
