defmodule AgentCore.Providers.Behavior do
  @moduledoc """
  Behavior for LLM provider implementations.

  This defines the contract that runtime implementations must follow
  for integrating with different LLM providers. The behavior abstracts
  provider-specific details and provides a uniform interface.
  """

  alias AgentCore.Providers.{Request, Response}

  @type provider_config :: map()
  @type request_options :: keyword()
  @type error :: term()

  @doc """
  Executes a request against the LLM provider.

  ## Parameters

  - `request` - The provider request containing model, messages, and parameters
  - `config` - Provider-specific configuration (API keys, endpoints, etc.)
  - `opts` - Additional request options (timeout, retries, etc.)

  ## Returns

  - `{:ok, response}` - Request completed successfully
  - `{:error, reason}` - Request failed
  """
  @callback execute(Request.t(), provider_config(), request_options()) ::
              {:ok, Response.t()} | {:error, error()}

  @doc """
  Performs a health check against the provider.

  ## Parameters

  - `config` - Provider-specific configuration
  - `opts` - Health check options

  ## Returns

  - `:ok` - Provider is healthy and reachable
  - `{:error, reason}` - Provider is unhealthy or unreachable
  """
  @callback health_check(provider_config(), request_options()) :: :ok | {:error, error()}

  @doc """
  Validates provider configuration.

  ## Parameters

  - `config` - Provider-specific configuration to validate

  ## Returns

  - `:ok` - Configuration is valid
  - `{:error, reason}` - Configuration is invalid
  """
  @callback validate_config(provider_config()) :: :ok | {:error, error()}

  @doc """
  Gets the supported models for this provider.

  ## Parameters

  - `config` - Provider-specific configuration

  ## Returns

  - `{:ok, models}` - List of supported model names
  - `{:error, reason}` - Failed to retrieve models
  """
  @callback supported_models(provider_config()) :: {:ok, [String.t()]} | {:error, error()}

  @doc """
  Estimates the cost of a request before execution.

  ## Parameters

  - `request` - The provider request to estimate cost for
  - `config` - Provider-specific configuration

  ## Returns

  - `{:ok, estimated_cost}` - Estimated cost in USD
  - `{:error, reason}` - Cost estimation failed
  """
  @callback estimate_cost(Request.t(), provider_config()) :: {:ok, float()} | {:error, error()}

  @doc """
  Transforms a generic request into provider-specific format.

  ## Parameters

  - `request` - The generic provider request
  - `config` - Provider-specific configuration

  ## Returns

  - `{:ok, provider_request}` - Transformed request ready for the provider
  - `{:error, reason}` - Transformation failed
  """
  @callback transform_request(Request.t(), provider_config()) :: {:ok, map()} | {:error, error()}

  @doc """
  Transforms a provider-specific response into generic format.

  ## Parameters

  - `provider_response` - The raw response from the provider
  - `config` - Provider-specific configuration

  ## Returns

  - `{:ok, response}` - Transformed generic response
  - `{:error, reason}` - Transformation failed
  """
  @callback transform_response(map(), provider_config()) ::
              {:ok, Response.t()} | {:error, error()}

  @optional_callbacks [
    estimate_cost: 2,
    transform_request: 2,
    transform_response: 2
  ]
end
