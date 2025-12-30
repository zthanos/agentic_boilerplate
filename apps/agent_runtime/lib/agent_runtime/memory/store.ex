defmodule AgentRuntime.Memory.Store do
  @moduledoc """
  Runtime abstraction for vector memory retrieval.

  Implementations live in outer layers (e.g. agent_web) and are injected via plan opts.
  """

  @type conversation_id :: Ecto.UUID.t() | String.t()
  @type embedding :: list(number())
  @type top_k :: pos_integer()

  @type result :: %{
          id: String.t(),
          text: String.t(),
          score: number()
        }

  @callback search(conversation_id(), embedding(), top_k()) :: [result()]
end
