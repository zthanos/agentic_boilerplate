defmodule AgentRuntime.MemoryStoreBehaviour do
  @callback search(binary(), list(number()), keyword()) ::
              {:ok, list(%{text: binary(), score: float()})} | {:error, term()}
end
