defmodule AgentRuntime.Providers.Registry do
  @moduledoc """
  Registry for provider implementations.

  This module manages the registration and lookup of provider implementations
  that can be used by the runtime system.
  """

  use GenServer
  require Logger

  @type provider_name :: atom()
  @type provider_module :: module()

  # Client API

  @doc """
  Starts the provider registry.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Registers a provider implementation.
  """
  @spec register_provider(provider_name(), provider_module()) :: :ok
  def register_provider(name, module) do
    GenServer.call(__MODULE__, {:register_provider, name, module})
  end

  @doc """
  Gets a provider implementation by name.
  """
  @spec get_provider(provider_name()) :: {:ok, provider_module()} | {:error, :not_found}
  def get_provider(name) do
    GenServer.call(__MODULE__, {:get_provider, name})
  end

  @doc """
  Lists all registered providers.
  """
  @spec list_providers() :: {:ok, [{provider_name(), provider_module()}]}
  def list_providers do
    GenServer.call(__MODULE__, :list_providers)
  end

  @doc """
  Unregisters a provider.
  """
  @spec unregister_provider(provider_name()) :: :ok
  def unregister_provider(name) do
    GenServer.call(__MODULE__, {:unregister_provider, name})
  end

  # GenServer callbacks

  @impl true
  def init(_opts) do
    # Register default providers
    providers = %{
      openai_compatible: AgentRuntime.Providers.OpenAICompatible,
      openai: AgentRuntime.Providers.OpenAICompatible,
      fake: AgentRuntime.Providers.Fake
    }

    Logger.info("Provider registry started with default providers",
      providers: Map.keys(providers)
    )

    {:ok, %{providers: providers}}
  end

  @impl true
  def handle_call({:register_provider, name, module}, _from, state) do
    Logger.info("Registering provider", name: name, module: module)

    updated_providers = Map.put(state.providers, name, module)
    new_state = %{state | providers: updated_providers}

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:get_provider, name}, _from, state) do
    case Map.get(state.providers, name) do
      nil -> {:reply, {:error, :not_found}, state}
      module -> {:reply, {:ok, module}, state}
    end
  end

  @impl true
  def handle_call(:list_providers, _from, state) do
    providers_list = Enum.to_list(state.providers)
    {:reply, {:ok, providers_list}, state}
  end

  @impl true
  def handle_call({:unregister_provider, name}, _from, state) do
    Logger.info("Unregistering provider", name: name)

    updated_providers = Map.delete(state.providers, name)
    new_state = %{state | providers: updated_providers}

    {:reply, :ok, new_state}
  end
end
