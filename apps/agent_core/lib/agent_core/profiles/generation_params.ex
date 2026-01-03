defmodule AgentCore.Profiles.GenerationParams do
  @moduledoc """
  Domain module for LLM generation parameters.

  Contains the configuration parameters that control how an LLM generates responses,
  such as temperature, max tokens, etc.
  """

  defstruct temperature: 0.7,
            max_tokens: nil,
            top_p: nil,
            top_k: nil,
            frequency_penalty: nil,
            presence_penalty: nil,
            seed: nil

  @type t :: %__MODULE__{
          temperature: float() | nil,
          max_tokens: integer() | nil,
          top_p: float() | nil,
          top_k: integer() | nil,
          frequency_penalty: float() | nil,
          presence_penalty: float() | nil,
          seed: integer() | nil
        }

  @doc """
  Creates new generation parameters with validation.
  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs \\ %{}) when is_map(attrs) do
    case validate_attrs(attrs) do
      :ok ->
        params = struct(__MODULE__, attrs)
        {:ok, params}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Converts generation parameters to a map.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = params) do
    params
    |> Map.from_struct()
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc """
  Creates generation parameters from a map.
  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    struct(__MODULE__, map)
  end

  @doc """
  Validates generation parameters.
  """
  @spec validate(t()) :: :ok | {:error, term()}
  def validate(%__MODULE__{} = params) do
    params
    |> Map.from_struct()
    |> validate_attrs()
  end

  # Private helpers

  defp validate_attrs(attrs) do
    with :ok <- validate_temperature(attrs[:temperature]),
         :ok <- validate_max_tokens(attrs[:max_tokens]),
         :ok <- validate_top_p(attrs[:top_p]),
         :ok <- validate_top_k(attrs[:top_k]),
         :ok <- validate_frequency_penalty(attrs[:frequency_penalty]),
         :ok <- validate_presence_penalty(attrs[:presence_penalty]),
         :ok <- validate_seed(attrs[:seed]) do
      :ok
    end
  end

  defp validate_temperature(nil), do: :ok
  defp validate_temperature(temp) when is_number(temp) and temp >= 0.0 and temp <= 2.0, do: :ok
  defp validate_temperature(_), do: {:error, :invalid_temperature}

  defp validate_max_tokens(nil), do: :ok
  defp validate_max_tokens(tokens) when is_integer(tokens) and tokens > 0, do: :ok
  defp validate_max_tokens(_), do: {:error, :invalid_max_tokens}

  defp validate_top_p(nil), do: :ok
  defp validate_top_p(p) when is_number(p) and p >= 0.0 and p <= 1.0, do: :ok
  defp validate_top_p(_), do: {:error, :invalid_top_p}

  defp validate_top_k(nil), do: :ok
  defp validate_top_k(k) when is_integer(k) and k > 0, do: :ok
  defp validate_top_k(_), do: {:error, :invalid_top_k}

  defp validate_frequency_penalty(nil), do: :ok

  defp validate_frequency_penalty(penalty)
       when is_number(penalty) and penalty >= -2.0 and penalty <= 2.0, do: :ok

  defp validate_frequency_penalty(_), do: {:error, :invalid_frequency_penalty}

  defp validate_presence_penalty(nil), do: :ok

  defp validate_presence_penalty(penalty)
       when is_number(penalty) and penalty >= -2.0 and penalty <= 2.0, do: :ok

  defp validate_presence_penalty(_), do: {:error, :invalid_presence_penalty}

  defp validate_seed(nil), do: :ok
  defp validate_seed(seed) when is_integer(seed), do: :ok
  defp validate_seed(_), do: {:error, :invalid_seed}
end
