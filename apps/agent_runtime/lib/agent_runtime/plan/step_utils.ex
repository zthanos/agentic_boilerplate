defmodule AgentRuntime.Llm.Plan.StepUtils do
  @moduledoc false

  alias AgentRuntime.Llm.Plan.PlanContext

  def last_user_prompt(%PlanContext{} = ctx) do
    ctx
    |> PlanContext.get_messages()
    |> Enum.reverse()
    |> Enum.find_value("", fn m ->
      role = Map.get(m, "role") || Map.get(m, :role)

      if role in ["user", :user] do
        Map.get(m, "content") || Map.get(m, :content)
      end
    end)
    |> to_string()
    |> String.trim()
  end

  def safe_json_decode(text) when is_binary(text) do
    with {:ok, map} when is_map(map) <- Jason.decode(text) do
      map
    else
      _ -> %{}
    end
  end

  def safe_json_decode(_), do: %{}

  def boolean(map, key, default \\ false) when is_map(map) do
    case Map.get(map, key) do
      true -> true
      false -> false
      _ -> default
    end
  end

  def string_or_nil(map, key) when is_map(map) do
    val = Map.get(map, key)

    cond do
      is_binary(val) ->
        v = String.trim(val)
        if v == "", do: nil, else: v

      true ->
        nil
    end
  end


  def enforce_null_when_false(map, bool_key, string_key) when is_map(map) do
    case boolean(map, bool_key, false) do
      true -> map
      false -> Map.put(map, string_key, nil)
    end
  end

  def extract_output_text(resp) when is_map(resp) do
    cond do
      is_binary(Map.get(resp, :output_text)) -> Map.get(resp, :output_text)
      is_binary(Map.get(resp, "output_text")) -> Map.get(resp, "output_text")
      is_binary(get_in(resp, [:message, :content])) -> get_in(resp, [:message, :content])
      is_binary(get_in(resp, ["message", "content"])) -> get_in(resp, ["message", "content"])
      true -> ""
    end
  end

  def extract_output_text(_), do: ""

end
