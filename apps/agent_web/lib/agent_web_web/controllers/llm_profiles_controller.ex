defmodule AgentWebWeb.LlmProfilesController do
  use AgentWebWeb, :controller

  alias AgentWeb.Llm.ProfileStoreEcto

  # GET /api/llm/profiles?enabled=true
  def index(conn, params) do
    list_opts = build_list_opts(params)
    profiles = ProfileStoreEcto.list(list_opts)

    json(conn, %{
      data: Enum.map(profiles, &profile_to_map/1)
    })
  end

  defp build_list_opts(%{"enabled" => enabled_str}) when is_binary(enabled_str) do
    case String.downcase(enabled_str) do
      "true" -> [enabled: true]
      "false" -> [enabled: false]
      _ -> []
    end
  end

  defp build_list_opts(_), do: []

  defp profile_to_map(p) do
    %{
      id: p.id,
      name: p.name,
      enabled: p.enabled,
      provider: p.provider,
      model: p.model,
      policy_version: p.policy_version,
      generation: p.generation,
      budgets: p.budgets,
      tools: p.tools,
      stop_list: p.stop_list,
      tags: p.tags,
      inserted_at: p.inserted_at,
      updated_at: p.updated_at
    }
  end
end
