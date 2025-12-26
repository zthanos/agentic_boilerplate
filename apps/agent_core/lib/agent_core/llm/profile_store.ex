defmodule AgentCore.Llm.ProfileStore do
  @moduledoc """
  Port for persisting and retrieving LLM profiles.

  Implementations live in web/runtime (Ecto, Memory, external, etc.).
  """

  alias AgentCore.Llm.LLMProfile

  @type id :: String.t() | atom()
  @type opts :: keyword()

  @callback put(LLMProfile.t()) :: {:ok, String.t()} | {:error, term()}
  @callback get(id()) :: {:ok, LLMProfile.t()} | :error
  @callback list(opts()) :: [LLMProfile.t()]
end
