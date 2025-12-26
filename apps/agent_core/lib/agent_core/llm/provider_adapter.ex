defmodule AgentCore.Llm.ProviderAdapter do
  @moduledoc """
  Provider adapter interface.

  Adapters are the ONLY place where provider/client specifics live.
  """

  alias AgentCore.Llm.ProviderRequest
  alias AgentCore.Llm.ProviderResponse

  @callback call(ProviderRequest.t()) ::
              {:ok, ProviderResponse.t()} | {:error, term()}
end
