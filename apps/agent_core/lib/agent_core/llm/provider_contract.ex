defmodule AgentCore.Llm.ProviderContract do
  @moduledoc "Builds canonical ProviderRequest from InvocationConfig + input."

  alias AgentCore.Llm.{InvocationConfig, ProviderRequest}

  @spec build_request(InvocationConfig.t(), map()) :: ProviderRequest.t()
  def build_request(%InvocationConfig{} = cfg, input) when is_map(input) do
    ProviderRequest.new(
      cfg,
      normalize_input!(input),
      Map.get(cfg, :tools, []),
      build_metadata(cfg)
    )
  end

  # -----------------------
  # Metadata (canonical)
  # -----------------------

  defp build_metadata(%InvocationConfig{} = cfg) do
    %{}
    |> put_if_present("fingerprint", Map.get(cfg, :fingerprint))
    |> put_if_present("trace_id", Map.get(cfg, :trace_id))
    |> put_if_present("profile_id", Map.get(cfg, :profile_id))
    |> put_if_present("provider", Map.get(cfg, :provider))
    |> put_if_present("model", Map.get(cfg, :model))
    |> put_if_present("policy_version", Map.get(cfg, :policy_version))
  end

  defp put_if_present(map, _k, nil), do: map

  defp put_if_present(map, k, v) do
    Map.put(map, k, normalize_meta_value(v))
  end

  defp normalize_meta_value(v) when is_binary(v), do: v
  defp normalize_meta_value(v) when is_atom(v), do: Atom.to_string(v)
  defp normalize_meta_value(v) when is_integer(v), do: Integer.to_string(v)
  defp normalize_meta_value(v), do: inspect(v)

  # -----------------------
  # Input normalization (canonical)
  # -----------------------

  defp normalize_input!(%{type: :chat, messages: msgs} = input) when is_list(msgs) do
    normalized =
      msgs
      |> Enum.map(&normalize_message!/1)

    %{input | messages: normalized}
  end

  defp normalize_input!(%{type: :completion, prompt: prompt} = input) when is_binary(prompt) do
    input
  end

  defp normalize_input!(other) do
    raise ArgumentError, "Invalid LLM input shape: #{inspect(other)}"
  end

  defp normalize_message!(%{role: role} = msg) when role in [:system, :user, :assistant, :tool] do
    # Canonical keys + avoid nil pollution
    %{}
    |> Map.put(:role, role)
    |> maybe_put(:content, Map.get(msg, :content))
    |> maybe_put(:name, Map.get(msg, :name))
    |> maybe_put(:tool_call_id, Map.get(msg, :tool_call_id))
    |> maybe_put(:metadata, normalize_message_metadata(Map.get(msg, :metadata)))
  end

  defp normalize_message!(other) do
    raise ArgumentError, "Invalid chat message: #{inspect(other)}"
  end

  defp maybe_put(map, _k, nil), do: map
  defp maybe_put(map, k, v), do: Map.put(map, k, v)

  defp normalize_message_metadata(nil), do: nil
  defp normalize_message_metadata(%{} = meta), do: meta
  defp normalize_message_metadata(other), do: %{"value" => inspect(other)}
end
