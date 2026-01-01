defmodule AgentRuntime.Llm.ExecutorBehaviour do
  @callback embed(binary(), map(), map(), map()) :: {:ok, list(number())} | {:error, term()}
  @callback chat(map(), map(), map(), map()) :: {:ok, map()} | {:error, term()}
end
