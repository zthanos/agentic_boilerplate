defmodule AgentWebWeb.LlmProfilesController do
  use AgentWebWeb, :controller

  alias AgentWeb.Llm

  def index(conn, params) do
    list_opts = build_list_opts(params)
    profiles = Llm.list_profiles(list_opts)

    json(conn, %{data: Enum.map(profiles, &profile_to_map/1)})
  end

  defp build_list_opts(params) do
    []
    |> maybe_put_enabled(params)
    |> maybe_put_provider(params)
    |> maybe_put_tag(params)
    |> maybe_put_q(params)
  end

  defp maybe_put_enabled(opts, %{"enabled" => v}) when is_binary(v) do
    case String.downcase(v) do
      "true" -> Keyword.put(opts, :enabled, true)
      "false" -> Keyword.put(opts, :enabled, false)
      _ -> opts
    end
  end

  defp maybe_put_enabled(opts, _), do: opts

  defp maybe_put_provider(opts, %{"provider" => v}) when is_binary(v) and byte_size(v) > 0,
    do: Keyword.put(opts, :provider, v)

  defp maybe_put_provider(opts, _), do: opts

  defp maybe_put_tag(opts, %{"tag" => v}) when is_binary(v) and byte_size(v) > 0,
    do: Keyword.put(opts, :tag, v)

  defp maybe_put_tag(opts, _), do: opts

  defp maybe_put_q(opts, %{"q" => v}) when is_binary(v) and byte_size(v) > 0,
    do: Keyword.put(opts, :q, v)

  defp maybe_put_q(opts, _), do: opts

  defp profile_to_map(p) do
    %{
      id: p.id,
      name: p.name,
      enabled: p.enabled,
      provider: to_string(p.provider),
      model: p.model,
      policy_version: p.policy_version,
      generation: p.generation,
      budgets: p.budgets,
      tools: p.tools,
      stop_list: p.stop_list,
      tags: p.tags,
      inserted_at: to_iso(p.inserted_at),
      updated_at: to_iso(p.updated_at)
    }
  end

  defp to_iso(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp to_iso(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_iso8601(ndt)
  defp to_iso(_), do: nil
end
