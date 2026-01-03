# defmodule AgentRuntime.Llm.Plan.StepUtils do
#   @moduledoc false

#   alias AgentRuntime.Llm.Plan.PlanContext

#   # -----------------------
#   # New: System prompt helpers
#   # -----------------------

#   @doc """
#   Resolve the effective system prompt with precedence:

#   1) ctx.exec_meta["agent_system_prompt"]
#   2) ctx.exec_meta["system_prompt"]
#   3) default_prompt (argument)
#   """
#   def system_prompt(%PlanContext{} = ctx, default_prompt \\ "") do
#     agent =
#       get_in(ctx.exec_meta || %{}, ["agent_system_prompt"]) ||
#         get_in(ctx.exec_meta || %{}, [:agent_system_prompt])

#     sys =
#       get_in(ctx.exec_meta || %{}, ["system_prompt"]) ||
#         get_in(ctx.exec_meta || %{}, [:system_prompt])

#     (agent || sys || default_prompt || "")
#     |> to_string()
#     |> String.trim()
#   end

#   @doc """
#   Build a system message map using the effective system prompt.
#   Returns nil if prompt is blank.
#   """
#   def system_message(%PlanContext{} = ctx, default_prompt \\ "") do
#     prompt = system_prompt(ctx, default_prompt)

#     if prompt == "" do
#       nil
#     else
#       %{"role" => "system", "content" => prompt}
#     end
#   end

#   # -----------------------
#   # Existing helpers
#   # -----------------------

#   def last_user_prompt(%PlanContext{} = ctx) do
#     ctx
#     |> PlanContext.get_messages()
#     |> Enum.reverse()
#     |> Enum.find_value("", fn m ->
#       role = Map.get(m, "role") || Map.get(m, :role)

#       if role in ["user", :user] do
#         Map.get(m, "content") || Map.get(m, :content)
#       end
#     end)
#     |> to_string()
#     |> String.trim()
#   end

#   def safe_json_decode(text) when is_binary(text) do
#     text
#     |> extract_json_object()
#     |> decode_json_object()
#   end

#   def safe_json_decode(_), do: %{}

#   defp extract_json_object(text) do
#     text = String.trim(text)

#     cond do
#       String.starts_with?(text, "{") and String.ends_with?(text, "}") ->
#         text

#       String.contains?(text, "```json") ->
#         case Regex.run(~r/```json\s*(\{.*?\})\s*```/s, text) do
#           [_, json] -> String.trim(json)
#           _ -> find_last_json_block(text)
#         end

#       true ->
#         find_last_json_block(text)
#     end
#   end

#   defp find_last_json_block(text) do
#     case :binary.matches(text, "{") do
#       [] ->
#         nil

#       positions ->
#         {last_open, _} = List.last(positions)
#         try_extract_from_position(text, last_open)
#     end
#   end

#   defp try_extract_from_position(text, start_pos) do
#     substring = String.slice(text, start_pos..-1//1)

#     case find_matching_brace(substring, 0, 0) do
#       nil -> nil
#       end_pos -> String.slice(substring, 0..end_pos)
#     end
#   end

#   defp find_matching_brace(<<>>, _pos, _depth), do: nil

#   defp find_matching_brace(<<"{", rest::binary>>, pos, depth) do
#     find_matching_brace(rest, pos + 1, depth + 1)
#   end

#   defp find_matching_brace(<<"}", _rest::binary>>, pos, 1), do: pos

#   defp find_matching_brace(<<"}", rest::binary>>, pos, depth) when depth > 1 do
#     find_matching_brace(rest, pos + 1, depth - 1)
#   end

#   defp find_matching_brace(<<_char, rest::binary>>, pos, depth) do
#     find_matching_brace(rest, pos + 1, depth)
#   end

#   defp decode_json_object(nil), do: %{}

#   defp decode_json_object(json) do
#     case Jason.decode(json) do
#       {:ok, map} when is_map(map) -> map
#       _ -> %{}
#     end
#   end

#   def boolean(map, key, default \\ false) when is_map(map) do
#     case Map.get(map, key) do
#       true -> true
#       false -> false
#       _ -> default
#     end
#   end

#   def string_or_nil(map, key) when is_map(map) do
#     val = Map.get(map, key)

#     cond do
#       is_binary(val) ->
#         v = String.trim(val)
#         if v == "", do: nil, else: v

#       true ->
#         nil
#     end
#   end

#   def require_nonblank_opt!(opts, key, step_name) when is_list(opts) do
#     val =
#       case key do
#         k when is_atom(k) ->
#           Keyword.get(opts, k) || Keyword.get(opts, Atom.to_string(k))

#         k when is_binary(k) ->
#           Keyword.get(opts, k) || Keyword.get(opts, String.to_atom(k))
#       end

#     cond do
#       is_binary(val) and String.trim(val) != "" ->
#         {:ok, String.trim(val)}

#       true ->
#         {:error, {:missing_or_blank, %{step: step_name, key: key}}}
#     end
#   end

#   def enforce_null_when_false(map, bool_key, string_key) when is_map(map) do
#     case boolean(map, bool_key, false) do
#       true -> map
#       false -> Map.put(map, string_key, nil)
#     end
#   end

#   def extract_output_text(resp) when is_map(resp) do
#     cond do
#       is_binary(Map.get(resp, :output_text)) -> Map.get(resp, :output_text)
#       is_binary(Map.get(resp, "output_text")) -> Map.get(resp, "output_text")
#       is_binary(get_in(resp, [:message, :content])) -> get_in(resp, [:message, :content])
#       is_binary(get_in(resp, ["message", "content"])) -> get_in(resp, ["message", "content"])
#       true -> ""
#     end
#   end

#   def extract_output_text(_), do: ""
# end
