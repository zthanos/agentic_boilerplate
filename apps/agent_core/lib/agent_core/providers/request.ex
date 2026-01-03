defmodule AgentCore.Providers.Request do
  @moduledoc """
  Domain model for LLM provider requests.

  Represents a standardized request that can be sent to any LLM provider.
  Provider implementations transform this into provider-specific formats.
  """

  @enforce_keys [:model, :messages]
  defstruct [
    :model,
    :messages,
    :system_message,
    temperature: 0.7,
    max_tokens: nil,
    top_p: nil,
    top_k: nil,
    frequency_penalty: nil,
    presence_penalty: nil,
    stop_sequences: [],
    tools: [],
    tool_choice: nil,
    seed: nil,
    stream: false,
    metadata: %{}
  ]

  @type message :: %{
          role: :system | :user | :assistant | :tool,
          content: String.t(),
          name: String.t() | nil,
          tool_calls: [map()] | nil,
          tool_call_id: String.t() | nil
        }

  @type tool_spec :: %{
          type: String.t(),
          function: %{
            name: String.t(),
            description: String.t() | nil,
            parameters: map() | nil
          }
        }

  @type tool_choice :: :auto | :none | %{type: String.t(), function: %{name: String.t()}}

  @type t :: %__MODULE__{
          model: String.t(),
          messages: [message()],
          system_message: String.t() | nil,
          temperature: float() | nil,
          max_tokens: integer() | nil,
          top_p: float() | nil,
          top_k: integer() | nil,
          frequency_penalty: float() | nil,
          presence_penalty: float() | nil,
          stop_sequences: [String.t()],
          tools: [tool_spec()],
          tool_choice: tool_choice() | nil,
          seed: integer() | nil,
          stream: boolean(),
          metadata: map()
        }

  @doc """
  Creates a new provider request.

  ## Examples

      iex> AgentCore.Providers.Request.new(
      ...>   model: "gpt-4",
      ...>   messages: [%{role: :user, content: "Hello"}]
      ...> )
      {:ok, %AgentCore.Providers.Request{...}}
  """
  @spec new(keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_list(attrs) do
    attrs_map = Map.new(attrs)

    case validate_required_fields(attrs_map) do
      :ok ->
        case validate_request_attrs(attrs_map) do
          :ok ->
            request = struct(__MODULE__, attrs_map)
            {:ok, request}

          {:error, _} = error ->
            error
        end

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Validates a provider request.
  """
  @spec validate(t()) :: :ok | {:error, term()}
  def validate(%__MODULE__{} = request) do
    request
    |> Map.from_struct()
    |> validate_request_attrs()
  end

  @doc """
  Adds a message to the request.
  """
  @spec add_message(t(), message()) :: t()
  def add_message(%__MODULE__{} = request, message) when is_map(message) do
    %{request | messages: request.messages ++ [message]}
  end

  @doc """
  Sets the system message for the request.
  """
  @spec set_system_message(t(), String.t()) :: t()
  def set_system_message(%__MODULE__{} = request, system_message)
      when is_binary(system_message) do
    %{request | system_message: system_message}
  end

  @doc """
  Adds tools to the request.
  """
  @spec add_tools(t(), [tool_spec()]) :: t()
  def add_tools(%__MODULE__{} = request, tools) when is_list(tools) do
    %{request | tools: request.tools ++ tools}
  end

  @doc """
  Sets generation parameters for the request.
  """
  @spec set_generation_params(t(), map()) :: t()
  def set_generation_params(%__MODULE__{} = request, params) when is_map(params) do
    Enum.reduce(params, request, fn {key, value}, acc ->
      case key do
        :temperature -> %{acc | temperature: value}
        :max_tokens -> %{acc | max_tokens: value}
        :top_p -> %{acc | top_p: value}
        :top_k -> %{acc | top_k: value}
        :frequency_penalty -> %{acc | frequency_penalty: value}
        :presence_penalty -> %{acc | presence_penalty: value}
        :seed -> %{acc | seed: value}
        _ -> acc
      end
    end)
  end

  @doc """
  Estimates the token count for the request.

  This is a rough estimation - actual token counting would be done
  by provider-specific implementations.
  """
  @spec estimate_tokens(t()) :: integer()
  def estimate_tokens(%__MODULE__{} = request) do
    message_tokens =
      request.messages
      |> Enum.map(&estimate_message_tokens/1)
      |> Enum.sum()

    system_tokens =
      case request.system_message do
        nil -> 0
        msg -> estimate_text_tokens(msg)
      end

    # Rough estimate
    tool_tokens = length(request.tools) * 50

    message_tokens + system_tokens + tool_tokens
  end

  # Private helpers

  defp validate_required_fields(attrs) do
    required_fields = [:model, :messages]

    missing_fields =
      required_fields
      |> Enum.reject(&Map.has_key?(attrs, &1))

    case missing_fields do
      [] -> :ok
      fields -> {:error, {:missing_required_fields, fields}}
    end
  end

  defp validate_request_attrs(attrs) do
    with :ok <- validate_model(attrs[:model]),
         :ok <- validate_messages(attrs[:messages]),
         :ok <- validate_temperature(attrs[:temperature]),
         :ok <- validate_max_tokens(attrs[:max_tokens]),
         :ok <- validate_tools(attrs[:tools]) do
      :ok
    end
  end

  defp validate_model(model) when is_binary(model) and byte_size(model) > 0, do: :ok
  defp validate_model(_), do: {:error, :invalid_model}

  defp validate_messages(messages) when is_list(messages) and length(messages) > 0 do
    if Enum.all?(messages, &valid_message?/1) do
      :ok
    else
      {:error, :invalid_messages}
    end
  end

  defp validate_messages(_), do: {:error, :invalid_messages}

  defp validate_temperature(nil), do: :ok
  defp validate_temperature(temp) when is_number(temp) and temp >= 0.0 and temp <= 2.0, do: :ok
  defp validate_temperature(_), do: {:error, :invalid_temperature}

  defp validate_max_tokens(nil), do: :ok
  defp validate_max_tokens(tokens) when is_integer(tokens) and tokens > 0, do: :ok
  defp validate_max_tokens(_), do: {:error, :invalid_max_tokens}

  defp validate_tools(nil), do: :ok
  defp validate_tools([]), do: :ok

  defp validate_tools(tools) when is_list(tools) do
    if Enum.all?(tools, &valid_tool?/1) do
      :ok
    else
      {:error, :invalid_tools}
    end
  end

  defp validate_tools(_), do: {:error, :invalid_tools}

  defp valid_message?(%{role: role, content: content})
       when role in [:system, :user, :assistant, :tool] and is_binary(content), do: true

  defp valid_message?(_), do: false

  defp valid_tool?(%{type: "function", function: %{name: name}})
       when is_binary(name), do: true

  defp valid_tool?(_), do: false

  defp estimate_message_tokens(%{content: content}) do
    estimate_text_tokens(content)
  end

  defp estimate_text_tokens(text) when is_binary(text) do
    # Rough estimation: ~4 characters per token
    div(String.length(text), 4) + 1
  end
end
