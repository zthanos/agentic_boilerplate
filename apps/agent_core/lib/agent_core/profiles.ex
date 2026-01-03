defmodule AgentCore.Profiles do
  @moduledoc """
  Domain module for LLM Profiles.

  A Profile represents a persisted, user-selectable configuration for invoking an LLM.
  This module contains the pure domain logic for profiles, including validation
  and configuration resolution.
  """

  alias AgentCore.Profiles.{GenerationParams, Budgets}

  @enforce_keys [:name, :provider, :model]
  defstruct [
    :id,
    :name,
    enabled: true,
    provider: nil,
    model: nil,
    policy_version: nil,
    generation: %GenerationParams{},
    budgets: %Budgets{},
    tools: [],
    stop_list: [],
    tags: [],
    created_at: nil,
    updated_at: nil
  ]

  @type id :: String.t() | integer()
  @type provider_type :: atom()
  @type model_ref :: String.t() | atom()

  @type t :: %__MODULE__{
          id: id() | nil,
          name: String.t(),
          enabled: boolean(),
          provider: provider_type(),
          model: model_ref(),
          policy_version: String.t() | nil,
          generation: GenerationParams.t(),
          budgets: Budgets.t(),
          tools: [String.t() | atom()],
          stop_list: [String.t()],
          tags: [String.t()],
          created_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @doc """
  Creates a new profile with the given attributes.

  ## Examples

      iex> AgentCore.Profiles.new(%{
      ...>   name: "GPT-4 Default",
      ...>   provider: :openai,
      ...>   model: "gpt-4"
      ...> })
      {:ok, %AgentCore.Profiles{...}}
  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    required_fields = [:name, :provider, :model]

    case validate_required_fields(attrs, required_fields) do
      :ok ->
        attrs_with_defaults =
          attrs
          |> Map.put_new(:enabled, true)
          |> Map.put_new(:generation, %GenerationParams{})
          |> Map.put_new(:budgets, %Budgets{})
          |> Map.put_new(:tools, [])
          |> Map.put_new(:stop_list, [])
          |> Map.put_new(:tags, [])

        case validate_profile_attrs(attrs_with_defaults) do
          :ok ->
            profile = struct(__MODULE__, attrs_with_defaults)
            {:ok, profile}

          {:error, _} = error ->
            error
        end

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Validates a profile's attributes.
  """
  @spec validate(t()) :: :ok | {:error, term()}
  def validate(%__MODULE__{} = profile) do
    profile
    |> Map.from_struct()
    |> validate_profile_attrs()
  end

  @doc """
  Resolves a profile's configuration into a map suitable for LLM invocation.
  """
  @spec resolve_config(t()) :: map()
  def resolve_config(%__MODULE__{} = profile) do
    %{
      provider: profile.provider,
      model: profile.model,
      generation_params: GenerationParams.to_map(profile.generation),
      budgets: Budgets.to_map(profile.budgets),
      tools: profile.tools,
      stop_list: profile.stop_list,
      policy_version: profile.policy_version
    }
  end

  @doc """
  Checks if a profile is enabled and can be used.
  """
  @spec enabled?(t()) :: boolean()
  def enabled?(%__MODULE__{enabled: enabled}), do: enabled

  @doc """
  Updates a profile with new attributes.
  """
  @spec update(t(), map()) :: {:ok, t()} | {:error, term()}
  def update(%__MODULE__{} = profile, attrs) when is_map(attrs) do
    updated_attrs =
      profile
      |> Map.from_struct()
      |> Map.merge(attrs)
      |> Map.put(:updated_at, DateTime.utc_now())

    case validate_profile_attrs(updated_attrs) do
      :ok ->
        updated_profile = struct(__MODULE__, updated_attrs)
        {:ok, updated_profile}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Generates a fingerprint for a profile configuration.
  Used for caching and run identification.
  """
  @spec fingerprint(t()) :: String.t()
  def fingerprint(%__MODULE__{} = profile) do
    config = resolve_config(profile)

    # Create a deterministic hash of the configuration
    config
    |> :erlang.term_to_binary()
    |> :crypto.hash(:sha256)
    |> Base.encode16(case: :lower)
  end

  # Private helpers

  defp validate_required_fields(attrs, required_fields) do
    missing_fields =
      required_fields
      |> Enum.reject(&Map.has_key?(attrs, &1))

    case missing_fields do
      [] -> :ok
      fields -> {:error, {:missing_required_fields, fields}}
    end
  end

  defp validate_profile_attrs(attrs) do
    with :ok <- validate_name(attrs[:name]),
         :ok <- validate_provider(attrs[:provider]),
         :ok <- validate_model(attrs[:model]),
         :ok <- validate_tools(attrs[:tools]),
         :ok <- validate_stop_list(attrs[:stop_list]),
         :ok <- validate_tags(attrs[:tags]) do
      :ok
    end
  end

  defp validate_name(name) when is_binary(name) and byte_size(name) > 0, do: :ok
  defp validate_name(_), do: {:error, :invalid_name}

  defp validate_provider(provider) when is_atom(provider), do: :ok
  defp validate_provider(_), do: {:error, :invalid_provider}

  defp validate_model(model) when is_binary(model) or is_atom(model), do: :ok
  defp validate_model(_), do: {:error, :invalid_model}

  defp validate_tools(tools) when is_list(tools) do
    if Enum.all?(tools, &(is_binary(&1) or is_atom(&1))) do
      :ok
    else
      {:error, :invalid_tools}
    end
  end

  defp validate_tools(_), do: {:error, :invalid_tools}

  defp validate_stop_list(stop_list) when is_list(stop_list) do
    if Enum.all?(stop_list, &is_binary/1) do
      :ok
    else
      {:error, :invalid_stop_list}
    end
  end

  defp validate_stop_list(_), do: {:error, :invalid_stop_list}

  defp validate_tags(tags) when is_list(tags) do
    if Enum.all?(tags, &is_binary/1) do
      :ok
    else
      {:error, :invalid_tags}
    end
  end

  defp validate_tags(_), do: {:error, :invalid_tags}
end
