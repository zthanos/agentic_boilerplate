defmodule AgentCore.TestAssessment.ConfigIssue do
  @moduledoc """
  Represents a configuration issue found in the test setup.
  """

  @derive Jason.Encoder

  @type issue_type ::
          :missing_dependency | :inconsistent_config | :invalid_setting | :deprecated_pattern

  @type t :: %__MODULE__{
          app_name: String.t(),
          file_path: String.t(),
          issue_type: issue_type(),
          severity: :warning | :error | :critical,
          description: String.t(),
          suggested_fix: String.t()
        }

  defstruct [
    :app_name,
    :file_path,
    :issue_type,
    :severity,
    :description,
    :suggested_fix
  ]
end
