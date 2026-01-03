defmodule AgentRuntime.Llm.Providers.OpenAICompatible do
  @moduledoc """
  OpenAI-compatible HTTP provider adapter.

  Works with LM Studio, OpenAI, and other OpenAI-compatible endpoints
  by changing OPENAI_COMPAT_BASE_URL / OPENAI_COMPAT_API_KEY.

  No streaming, no tools execution (out of scope).
  """

  @behaviour AgentCore.Providers.Behavior
  require Logger
  alias AgentCore.Providers.{Request, Response}
  alias AgentRuntime.Llm.ModelResolver
  alias AgentRuntime.Llm.HttpClient.FinchClient
  alias AgentRuntime.Llm.ProviderConfig

  @chat_path "/chat/completions"
  @completion_path "/completions"
  @embeddings_path "/embeddings"

  # Legacy interface for backward compatibility
  def call(%AgentCore.Llm.ProviderRequest{} = req) do
    # Convert from legacy request format to new format
    provider_request = %Request{
      model: req.invocation.model,
      messages: req.input.messages,
      system_message: nil,
      temperature: req.invocation.generation[:temperature],
      max_tokens: req.invocation.generation[:max_tokens],
      top_p: req.invocation.generation[:top_p],
      top_k: req.invocation.generation[:top_k],
      frequency_penalty: req.invocation.generation[:frequency_penalty],
      presence_penalty: req.invocation.generation[:presence_penalty],
      stop_sequences: req.invocation.generation[:stop_sequences],
      tools: req.tools || [],
      tool_choice: req.invocation.generation[:tool_choice],
      seed: req.invocation.generation[:seed],
      stream: req.invocation.generation[:stream] || false,
      metadata: req.metadata || %{}
    }

    # Get config from environment
    config = %{
      base_url: System.get_env("OPENAI_BASE_URL", "https://api.openai.com/v1"),
      api_key: System.get_env("OPENAI_API_KEY"),
      timeout_ms: 30_000,
      connect_timeout_ms: 5_000
    }

    execute(provider_request, config)
  end

  @impl true
  def execute(%Request{} = req, config, opts \\ []) do
    model = req.model

    with {:ok, {path, payload}} <- build_request(req) do
      Logger.info(
        "[llm] CALL provider=openai_compatible url=#{config.base_url <> path} model=#{inspect(model)}"
      )

      with {:ok, body} <- json_encode(payload),
           {:ok, %{} = resp_map} <-
             http_post(
               config.base_url <> path,
               body,
               config.api_key,
               config.timeout_ms,
               config.connect_timeout_ms
             ),
           {:ok, provider_resp} <- parse_response(req, resp_map) do
        {:ok, provider_resp}
      end
    end
  end

  @impl true
  def health_check(config, _opts \\ []) do
    # Simple health check - try to get models list
    case http_get(config.base_url <> "/models", config.api_key, 5000) do
      {:ok, _response} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def validate_config(config) do
    required_keys = [:base_url, :api_key]

    missing_keys =
      Enum.filter(required_keys, fn key ->
        not Map.has_key?(config, key) or is_nil(Map.get(config, key))
      end)

    if missing_keys == [] do
      :ok
    else
      {:error, {:missing_config_keys, missing_keys}}
    end
  end

  @impl true
  def supported_models(config) do
    case http_get(config.base_url <> "/models", config.api_key, 5000) do
      {:ok, %{"data" => models}} when is_list(models) ->
        model_names = Enum.map(models, fn model -> Map.get(model, "id") end)
        {:ok, model_names}

      {:ok, _response} ->
        {:error, :invalid_models_response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def estimate_cost(%Request{} = _request, _config) do
    # Cost estimation not implemented for OpenAI compatible providers
    {:error, :cost_estimation_not_supported}
  end

  @impl true
  def transform_request(%Request{} = request, _config) do
    # Transform to OpenAI format
    case build_request(request) do
      {:ok, {_path, payload}} -> {:ok, payload}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def transform_response(raw_response, _config) do
    # Parse OpenAI response format
    case parse_openai_response(raw_response) do
      {:ok, response} -> {:ok, response}
      {:error, reason} -> {:error, reason}
    end
  end

  # -------------------------
  # Build request
  # -------------------------

  defp build_request(%Request{messages: msgs} = req) when is_list(msgs) do
    {:ok,
     {@chat_path,
      %{
        "model" => ModelResolver.resolve(:openai_compatible, req.model),
        "messages" => Enum.map(msgs || [], &normalize_chat_message/1),
        "temperature" => req.temperature,
        "top_p" => req.top_p,
        "max_tokens" => req.max_tokens
      }
      |> drop_nil_values()}}
  end

  defp build_request(%Request{} = req),
    do: {:error, {:unsupported_request_format, req}}

  defp normalize_chat_message(m) do
    %{
      "role" => m.role |> to_string(),
      "content" => Map.get(m, :content)
    }
    |> maybe_put("name", Map.get(m, :name))
    |> maybe_put("tool_call_id", Map.get(m, :tool_call_id))
  end

  defp maybe_put(map, _k, nil), do: map
  defp maybe_put(map, k, v), do: Map.put(map, k, v)

  defp drop_nil_values(map) do
    map
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  # -------------------------
  # Stream support
  # -------------------------
  @impl false
  def stream(%Request{} = req, on_chunk) when is_function(on_chunk, 1) do
    # Streaming not implemented for the new behavior interface
    {:error, :streaming_not_supported}
  end

  # -------------------------
  # HTTP (no extra deps)
  # -------------------------
  defp http_post(url, body, api_key, timeout_ms, connect_timeout_ms) do
    headers =
      [
        {~c"content-type", ~c"application/json"}
      ]
      |> maybe_auth(api_key)

    http_opts = [
      timeout: timeout_ms,
      connect_timeout: connect_timeout_ms
    ]

    case http_client().post(
           to_charlist(url),
           headers,
           to_charlist(body),
           http_opts,
           body_format: :binary
         ) do
      {:ok, {{_http, status, _reason}, _resp_headers, resp_body}} when status in 200..299 ->
        json_decode(resp_body)

      {:ok, {{_http, status, _reason}, _resp_headers, resp_body}} ->
        {:error, {:http_error, status, resp_body}}

      {:error, reason} ->
        {:error, {:http_error, reason}}
    end
  end

  defp http_get(url, api_key, timeout_ms) do
    headers = [] |> maybe_auth(api_key)

    http_opts = [
      timeout: timeout_ms,
      connect_timeout: 5_000
    ]

    # Note: Using POST with empty body since the HttpClient behavior only defines post/5
    case http_client().post(
           to_charlist(url),
           headers,
           ~c"",
           http_opts,
           body_format: :binary
         ) do
      {:ok, {{_http, status, _reason}, _resp_headers, resp_body}} when status in 200..299 ->
        json_decode(resp_body)

      {:ok, {{_http, status, _reason}, _resp_headers, resp_body}} ->
        {:error, {:http_error, status, resp_body}}

      {:error, reason} ->
        {:error, {:http_error, reason}}
    end
  end

  defp http_client do
    Application.get_env(:agent_runtime, :llm_http_client, AgentRuntime.Llm.HttpClient.Default)
  end

  defp maybe_auth(headers, nil), do: headers
  defp maybe_auth(headers, ""), do: headers

  defp maybe_auth(headers, api_key),
    do: [{~c"authorization", to_charlist("Bearer " <> api_key)} | headers]

  defp json_encode(map) do
    {:ok, Jason.encode!(map)}
  rescue
    e -> {:error, {:json_encode_failed, e}}
  end

  defp json_decode(bin) when is_binary(bin) do
    {:ok, Jason.decode!(bin)}
  rescue
    e -> {:error, {:json_decode_failed, e, bin}}
  end

  # -------------------------
  # Parse response
  # -------------------------

  defp parse_response(%Request{messages: _msgs}, %{"choices" => [c | _]} = raw) do
    text =
      c
      |> Map.get("message", %{})
      |> Map.get("content", "")
      |> to_string()

    usage = Map.get(raw, "usage", %{})
    {:ok, Response.success(text, raw: raw, usage: usage, finish_reason: c["finish_reason"])}
  end

  defp parse_response(_req, raw),
    do: {:error, {:unexpected_response_shape, raw}}

  defp parse_openai_response(%{"choices" => [c | _]} = raw) do
    text =
      c
      |> Map.get("message", %{})
      |> Map.get("content", "")
      |> to_string()

    usage = Map.get(raw, "usage", %{})
    {:ok, Response.success(text, raw: raw, usage: usage, finish_reason: c["finish_reason"])}
  end

  defp parse_openai_response(raw),
    do: {:error, {:unexpected_response_shape, raw}}
end
