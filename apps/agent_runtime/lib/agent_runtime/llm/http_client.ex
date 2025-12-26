defmodule AgentRuntime.Llm.HttpClient do
  @callback post(
              url :: charlist(),
              headers :: list(),
              body :: charlist(),
              http_opts :: list(),
              opts :: list()
            ) ::
              {:ok, {{term(), non_neg_integer(), term()}, list(), binary()}} | {:error, term()}
end
