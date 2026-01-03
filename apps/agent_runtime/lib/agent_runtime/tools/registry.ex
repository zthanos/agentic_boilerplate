defmodule AgentRuntime.Tools.Registry do
  @moduledoc """
  Registry for tool implementations.

  This module manages the registration and lookup of tool implementations
  that can be used by the runtime system.
  """

  use GenServer
  require Logger

  alias AgentCore.Tools.Behavior

  @type tool_name :: String.t() | atom()
  @type tool_module :: module()

  # Client API

  @doc """
  Starts the tool registry.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Registers a tool implementation.
  """
  @spec register_tool(tool_name(), tool_module()) :: :ok | {:error, term()}
  def register_tool(name, module) do
    GenServer.call(__MODULE__, {:register_tool, name, module})
  end

  @doc """
  Gets a tool implementation by name.
  """
  @spec get_tool(tool_name()) :: {:ok, tool_module()} | {:error, :not_found}
  def get_tool(name) do
    GenServer.call(__MODULE__, {:get_tool, name})
  end

  @doc """
  Lists all registered tools.
  """
  @spec list_tools() :: {:ok, [{tool_name(), tool_module()}]}
  def list_tools do
    GenServer.call(__MODULE__, :list_tools)
  end

  @doc """
  Unregisters a tool.
  """
  @spec unregister_tool(tool_name()) :: :ok
  def unregister_tool(name) do
    GenServer.call(__MODULE__, {:unregister_tool, name})
  end

  @doc """
  Registers multiple tools from a module.
  """
  @spec register_tools_from_module(module()) :: :ok | {:error, term()}
  def register_tools_from_module(module) do
    GenServer.call(__MODULE__, {:register_tools_from_module, module})
  end

  @doc """
  Gets all tool specifications.
  """
  @spec get_all_tool_specs() :: {:ok, map()} | {:error, term()}
  def get_all_tool_specs do
    GenServer.call(__MODULE__, :get_all_tool_specs)
  end

  # GenServer callbacks

  @impl true
  def init(_opts) do
    Logger.info("Tool registry started")

    state = %{
      tools: %{},
      tool_specs: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:register_tool, name, module}, _from, state) do
    if Behavior.tool_module?(module) do
      Logger.info("Registering tool", name: name, module: module)

      # Get tool specification
      spec = Behavior.get_tool_spec(module)

      updated_tools = Map.put(state.tools, name, module)
      updated_specs = Map.put(state.tool_specs, name, spec)

      new_state = %{state | tools: updated_tools, tool_specs: updated_specs}

      {:reply, :ok, new_state}
    else
      Logger.error("Invalid tool module", name: name, module: module)
      {:reply, {:error, {:invalid_tool_module, module}}, state}
    end
  end

  @impl true
  def handle_call({:get_tool, name}, _from, state) do
    case Map.get(state.tools, name) do
      nil -> {:reply, {:error, :not_found}, state}
      module -> {:reply, {:ok, module}, state}
    end
  end

  @impl true
  def handle_call(:list_tools, _from, state) do
    tools_list = Enum.to_list(state.tools)
    {:reply, {:ok, tools_list}, state}
  end

  @impl true
  def handle_call({:unregister_tool, name}, _from, state) do
    Logger.info("Unregistering tool", name: name)

    updated_tools = Map.delete(state.tools, name)
    updated_specs = Map.delete(state.tool_specs, name)

    new_state = %{state | tools: updated_tools, tool_specs: updated_specs}

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:register_tools_from_module, module}, _from, state) do
    try do
      # Look for tool functions in the module
      tool_functions = get_tool_functions(module)

      {updated_tools, updated_specs} =
        Enum.reduce(tool_functions, {state.tools, state.tool_specs}, fn {name, tool_module},
                                                                        {tools_acc, specs_acc} ->
          if Behavior.tool_module?(tool_module) do
            spec = Behavior.get_tool_spec(tool_module)

            {
              Map.put(tools_acc, name, tool_module),
              Map.put(specs_acc, name, spec)
            }
          else
            {tools_acc, specs_acc}
          end
        end)

      new_state = %{state | tools: updated_tools, tool_specs: updated_specs}

      Logger.info("Registered tools from module",
        module: module,
        tool_count: map_size(updated_tools) - map_size(state.tools)
      )

      {:reply, :ok, new_state}
    rescue
      exception ->
        Logger.error("Failed to register tools from module",
          module: module,
          exception: Exception.message(exception)
        )

        {:reply, {:error, {:registration_failed, Exception.message(exception)}}, state}
    end
  end

  @impl true
  def handle_call(:get_all_tool_specs, _from, state) do
    {:reply, {:ok, state.tool_specs}, state}
  end

  # Private helper functions

  defp get_tool_functions(module) do
    # This is a simplified implementation
    # In a real system, you might use reflection or conventions
    # to discover tool functions within a module
    []
  end
end
