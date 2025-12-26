defmodule AgentWeb.Llm.ExecuteRequest do
  @enforce_keys [:profile_id, :input]
  defstruct [:profile_id, :input, :overrides]

  @type t :: %__MODULE__{
          profile_id: String.t(),
          input: map(),
          overrides: map()
        }

  def from_params(%{"profile_id" => pid, "input" => input} = params)
      when is_binary(pid) and is_map(input) do
    overrides =
      case Map.get(params, "overrides", %{}) do
        o when is_map(o) -> o
        _ -> %{}
      end

    {:ok, %__MODULE__{profile_id: pid, input: input, overrides: overrides}}
  end

  def from_params(_), do: {:error, :invalid_request}
end
