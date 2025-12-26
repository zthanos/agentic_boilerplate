defmodule AgentCore.Llm.Provider do

  alias __MODULE__

  @enforce_keys [:type, :base_url]
  defstruct [
    :type,
    :base_url,
    :api_key,
    :default_headers,
    :request_timeout_ms,
    :retries,
    :retry_backoff_ms
  ]

  @type t :: %Provider{
    type: atom(),
    base_url: String.t(),
    api_key: String.t() | nil,
    default_headers: map() | nil,
    request_timeout_ms: integer(),
    retries: integer(),
    retry_backoff_ms: integer()
  }

end
