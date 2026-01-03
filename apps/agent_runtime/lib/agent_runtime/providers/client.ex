defmodule AgentRuntime.Providers.Client do
  @moduledoc """
  Runtime client for executing provider requests.

  This module provides the runtime implementation for provider execution,
  delegating to specific provider implementations based on the provider type.
  """

  alias AgentCore.Providers.{Request, Response}
  alias AgentRuntime.Providers.{OpenAICompatible, Registry}

  require Logger

  @type provider_config :: map()
  @type request_options :: keyword()
  @type client_result :: {:ok, Response.t()} | {:error, term()}

  @doc """
  Executes a provider request.

  ## Parameters

  - `request` - The provider request
  - `config` - Provider-specific configuration
  - `opts` - Request options

  ## Returns

  - `{:ok, response}` - Request executed successfully
  - `{:error, reason}` - Request execution failed
  """
  @spec execute_request(Request.t(), provider_config(), request_options()) :: client_result()
  def execute_request(%Request{} = request, config, opts \\ []) do
    Logger.info("Executing provider request",
      provider: request.provider,
      model: request.model
    )

    with {:ok, provider_module} <- get_provider_module(request.provider),
         {:ok, validated_config} <- validate_provider_config(provider_module, config) do
      provider_module.execute(request, validated_config, opts)
    else
      {:error, reason} ->
        Logger.error("Provider request failed",
          provider: request.provider,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  @doc """
  Performs a health check for a provider.
  """
  @spec health_check(atom(), provider_config(), request_options()) :: :ok | {:error, term()}
  def health_check(provider, config, opts \\ []) do
    with {:ok, provider_module} <- get_provider_module(provider) do
      provider_module.health_check(config, opts)
    end
  end

  @doc """
  Gets supported models for a provider.
  """
  @spec supported_models(atom(), provider_config()) :: {:ok, [String.t()]} | {:error, term()}
  def supported_models(provider, config) do
    with {:ok, provider_module} <- get_provider_module(provider) do
      provider_module.supported_models(config)
    end
  end

  @doc """
  Estimates the cost of a provider request.
  """
  @spec estimate_cost(Request.t(), provider_config()) :: {:ok, float()} | {:error, term()}
  def estimate_cost(%Request{} = request, config) do
    with {:ok, provider_module} <- get_provider_module(request.provider) do
      if function_exported?(provider_module, :estimate_cost, 2) do
        provider_module.estimate_cost(request, config)
      else
        {:error, :cost_estimation_not_supported}
      end
    end
  end

  # Private helper functions

  defp get_provider_module(provider) do
    case Registry.get_provider(provider) do
      {:ok, module} -> {:ok, module}
      {:error, :not_found} -> get_default_provider_module(provider)
    end
  end

  defp get_default_provider_module(provider) do
    case provider do
      :openai_compatible -> {:ok, AgentRuntime.Providers.OpenAICompatible}
      :openai -> {:ok, AgentRuntime.Providers.OpenAICompatible}
      :anthropic -> {:error, {:provider_not_implemented, provider}}
      :google -> {:error, {:provider_not_implemented, provider}}
      _ -> {:error, {:unknown_provider, provider}}
    end
  end

  defp validate_provider_config(provider_module, config) do
    if function_exported?(provider_module, :validate_config, 1) do
      provider_module.validate_config(config)
    else
      {:ok, config}
    end
  end
end
