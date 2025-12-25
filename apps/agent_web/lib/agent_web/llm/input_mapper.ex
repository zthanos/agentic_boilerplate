defmodule AgentWeb.Llm.InputMapper do
  @moduledoc false

  @allowed_roles ~w(system user assistant tool developer)

  @spec to_runtime(map()) :: {:ok, map()} | {:error, term()}
  def to_runtime(%{"type" => "chat", "messages" => messages}) when is_list(messages) do
    with {:ok, msgs} <- map_messages(messages) do
      {:ok, %{type: :chat, messages: msgs}}
    end
  end

  def to_runtime(%{"type" => "completion", "prompt" => prompt}) when is_binary(prompt) do
    {:ok, %{type: :completion, prompt: prompt}}
  end

  def to_runtime(other), do: {:error, {:unsupported_input, other}}

  defp map_messages(messages) do
    messages
    |> Enum.map(&map_message/1)
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, m}, {:ok, acc} -> {:cont, {:ok, [m | acc]}}
      {:error, r}, _ -> {:halt, {:error, r}}
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      err -> err
    end
  end

  defp map_message(%{"role" => role, "content" => content})
       when is_binary(role) and is_binary(content) do
    role = String.downcase(role)

    if role in @allowed_roles do
      {:ok, %{role: String.to_atom(role), content: content}}
    else
      {:error, {:invalid_role, role}}
    end
  end

  defp map_message(other), do: {:error, {:invalid_message, other}}
end
