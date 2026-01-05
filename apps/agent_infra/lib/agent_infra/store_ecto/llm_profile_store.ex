defmodule AgentInfra.StoreEcto.LLMProfileStore do
  @moduledoc """
  Ecto implementation of the LLMProfileStore behavior.

  This module implements the AgentCore.Stores.LLMProfileStore behavior using Ecto
  and the existing Profile schema for persistence. It handles conversion between
  LLMProfile domain structs and database schemas.
  """

  @behaviour AgentCore.Stores.LLMProfileStore

  alias AgentCore.Llm.LLMProfile
  alias AgentCore.Stores.LLMProfileStore
  alias AgentInfra.{Repo, Schema.Profile}
  import Ecto.Query

  @impl LLMProfileStore
  def put(%LLMProfile{} = profile) do
    attrs = llm_profile_to_schema_attrs(profile)

    case profile.id do
      nil ->
        # Create new profile
        %Profile{}
        |> Profile.changeset(attrs)
        |> Repo.insert()
        |> case do
          {:ok, schema} -> {:ok, schema.id}
          {:error, changeset} -> {:error, changeset}
        end

      id ->
        # Update existing profile
        case Repo.get(Profile, to_string(id)) do
          nil ->
            # Create with specific ID
            attrs = Map.put(attrs, :id, to_string(id))

            %Profile{}
            |> Profile.changeset(attrs)
            |> Repo.insert()
            |> case do
              {:ok, schema} -> {:ok, schema.id}
              {:error, changeset} -> {:error, changeset}
            end

          schema ->
            # Update existing
            schema
            |> Profile.changeset(attrs)
            |> Repo.update()
            |> case do
              {:ok, updated_schema} -> {:ok, updated_schema.id}
              {:error, changeset} -> {:error, changeset}
            end
        end
    end
  end

  @impl LLMProfileStore
  def get(profile_id) do
    case Repo.get(Profile, to_string(profile_id)) do
      nil -> :error
      schema -> {:ok, schema_to_llm_profile(schema)}
    end
  end

  @impl LLMProfileStore
  def list(opts \\ []) do
    query = build_list_query(opts)

    try do
      profiles =
        query
        |> Repo.all()
        |> Enum.map(&schema_to_llm_profile/1)

      profiles
    rescue
      _error -> []
    end
  end

  @impl LLMProfileStore
  def delete(profile_id) do
    case Repo.get(Profile, to_string(profile_id)) do
      nil ->
        {:error, :not_found}

      schema ->
        case Repo.delete(schema) do
          {:ok, _} -> :ok
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  @impl LLMProfileStore
  def name_available?(name) when is_binary(name) do
    query = from(p in Profile, where: p.name == ^name)

    case Repo.one(query) do
      nil -> true
      _profile -> false
    end
  end

  # Private helper functions

  defp llm_profile_to_schema_attrs(%LLMProfile{} = profile) do
    %{
      id: profile.id && to_string(profile.id),
      name: profile.name,
      enabled: profile.enabled,
      provider_id: to_string(profile.provider_id),
      model: to_string(profile.model),
      policy_version: profile.policy_version,
      generation: generation_params_to_map(profile.generation),
      budgets: budgets_to_map(profile.budgets),
      tools: Enum.map(profile.tools, &to_string/1),
      stop_list: profile.stop_list,
      tags: profile.tags
    }
  end

  defp schema_to_llm_profile(%Profile{} = schema) do
    %LLMProfile{
      id: schema.id,
      name: schema.name,
      enabled: schema.enabled,
      provider_id: schema.provider_id,
      model: schema.model,
      policy_version: schema.policy_version,
      generation: map_to_generation_params(schema.generation || %{}),
      budgets: map_to_budgets(schema.budgets || %{}),
      tools: schema.tools || [],
      stop_list: schema.stop_list || [],
      tags: schema.tags || [],
      inserted_at: schema.inserted_at,
      updated_at: schema.updated_at
    }
  end

  defp generation_params_to_map(%AgentCore.Llm.GenerationParams{} = params) do
    %{
      temperature: params.temperature,
      top_p: params.top_p,
      max_output_tokens: params.max_output_tokens,
      seed: params.seed,
      presence_penalty: params.presence_penalty,
      frequency_penalty: params.frequency_penalty,
      stop: params.stop
    }
  end

  defp generation_params_to_map(params) when is_map(params), do: params

  defp map_to_generation_params(map) when is_map(map) do
    %AgentCore.Llm.GenerationParams{
      temperature: Map.get(map, :temperature) || Map.get(map, "temperature") || 0.2,
      top_p: Map.get(map, :top_p) || Map.get(map, "top_p") || 1.0,
      max_output_tokens: Map.get(map, :max_output_tokens) || Map.get(map, "max_output_tokens"),
      seed: Map.get(map, :seed) || Map.get(map, "seed"),
      presence_penalty: Map.get(map, :presence_penalty) || Map.get(map, "presence_penalty"),
      frequency_penalty: Map.get(map, :frequency_penalty) || Map.get(map, "frequency_penalty"),
      stop: Map.get(map, :stop) || Map.get(map, "stop")
    }
  end

  defp budgets_to_map(%AgentCore.Llm.Budgets{} = budgets) do
    %{
      max_input_tokens: budgets.max_input_tokens,
      max_output_tokens: budgets.max_output_tokens,
      max_total_tokens: budgets.max_total_tokens,
      max_cost_eur: budgets.max_cost_eur,
      max_steps: budgets.max_steps
    }
  end

  defp budgets_to_map(budgets) when is_map(budgets), do: budgets

  defp map_to_budgets(map) when is_map(map) do
    %AgentCore.Llm.Budgets{
      max_input_tokens: Map.get(map, :max_input_tokens) || Map.get(map, "max_input_tokens"),
      max_output_tokens: Map.get(map, :max_output_tokens) || Map.get(map, "max_output_tokens"),
      max_total_tokens: Map.get(map, :max_total_tokens) || Map.get(map, "max_total_tokens"),
      max_cost_eur: Map.get(map, :max_cost_eur) || Map.get(map, "max_cost_eur"),
      max_steps: Map.get(map, :max_steps) || Map.get(map, "max_steps")
    }
  end

  defp build_list_query(opts) do
    base_query = from(p in Profile)

    Enum.reduce(opts, base_query, fn
      {:enabled, enabled}, q ->
        from(p in q, where: p.enabled == ^enabled)

      {:provider, provider}, q ->
        from(p in q, where: p.provider_id == ^to_string(provider))

      {:tags, tags}, q when is_list(tags) ->
        from(p in q, where: fragment("? && ?", p.tags, ^tags))

      {:limit, limit}, q ->
        from(p in q, limit: ^limit)

      {:offset, offset}, q ->
        from(p in q, offset: ^offset)

      _other, q ->
        q
    end)
  end
end
