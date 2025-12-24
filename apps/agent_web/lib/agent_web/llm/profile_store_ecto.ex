defmodule AgentWeb.Llm.ProfileStoreEcto do
  @behaviour AgentCore.Llm.ProfileStore
  @moduledoc "Ecto-backed persistence for LLM profiles."

  alias AgentWeb.Repo
  alias AgentWeb.Schemas.ProfileRecord
  alias AgentCore.Llm.LLMProfile
  alias AgentCore.RunStore.Serialization


  @spec put(LLMProfile.t()) :: {:ok, String.t()} | {:error, Ecto.Changeset.t()}
  def put(%LLMProfile{} = profile) do
    attrs = %{
      id: to_string(profile.id),
      name: profile.name,
      enabled: profile.enabled,
      provider: to_string(profile.provider),
      model: to_string(profile.model),
      policy_version: profile.policy_version && to_string(profile.policy_version),
      generation: Serialization.deep_jsonify(profile.generation || %{}),
      budgets: Serialization.deep_jsonify(profile.budgets || %{}),
      tools: Enum.map(profile.tools || [], &to_string/1),
      stop_list: Enum.map(profile.stop_list || [], &to_string/1),
      tags: Enum.map(profile.tags || [], &to_string/1)
    }

    %ProfileRecord{}
    |> ProfileRecord.changeset(attrs)
    |> Repo.insert(
      on_conflict:
        {:replace,
         [
           :name,
           :enabled,
           :provider,
           :model,
           :policy_version,
           :generation,
           :budgets,
           :tools,
           :stop_list,
           :tags,
           :updated_at
         ]},
      conflict_target: :id
    )
    |> case do
      {:ok, _rec} -> {:ok, attrs.id}
      {:error, cs} -> {:error, cs}
    end
  end

  @spec get(String.t() | atom()) :: {:ok, AgentCore.Llm.LLMProfile.t()} | :error
  def get(id) do
    case Repo.get(ProfileRecord, to_string(id)) do
      nil -> :error
      rec -> {:ok, to_domain(rec)}
    end
  end


  @spec list(keyword()) :: [LLMProfile.t()]
  def list(opts \\ []) do
    profiles =
      Repo.all(ProfileRecord)
      |> Enum.map(&to_domain/1)

    case Keyword.get(opts, :enabled) do
      nil -> profiles
      flag when is_boolean(flag) -> Enum.filter(profiles, &(&1.enabled == flag))
      _ -> profiles
    end
  end

  # -----------------------
  # Mapping
  # -----------------------

  defp to_domain(%ProfileRecord{} = rec) do
    %LLMProfile{
      id: rec.id,
      name: rec.name,
      enabled: rec.enabled,
      provider: safe_to_atom(rec.provider),
      model: safe_to_atom(rec.model),
      policy_version: rec.policy_version,
      generation: rec.generation || %{},
      budgets: rec.budgets || %{},
      tools: rec.tools || [],
      stop_list: rec.stop_list || [],
      tags: rec.tags || []
    }
  end

  defp safe_to_atom(nil), do: nil

  defp safe_to_atom(s) when is_binary(s) do
    String.to_existing_atom(s)
  rescue
    ArgumentError -> s
  end



end
