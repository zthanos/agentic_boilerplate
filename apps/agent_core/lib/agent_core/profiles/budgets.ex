defmodule AgentCore.Profiles.Budgets do
  @moduledoc """
  Domain module for LLM usage budgets and limits.

  Contains budget constraints and limits for LLM usage, such as token limits,
  cost limits, and rate limits.
  """

  defstruct max_tokens_per_request: nil,
            max_tokens_per_day: nil,
            max_cost_per_request: nil,
            max_cost_per_day: nil,
            max_requests_per_minute: nil,
            max_requests_per_hour: nil,
            max_requests_per_day: nil

  @type t :: %__MODULE__{
          max_tokens_per_request: integer() | nil,
          max_tokens_per_day: integer() | nil,
          max_cost_per_request: float() | nil,
          max_cost_per_day: float() | nil,
          max_requests_per_minute: integer() | nil,
          max_requests_per_hour: integer() | nil,
          max_requests_per_day: integer() | nil
        }

  @doc """
  Creates new budget constraints with validation.
  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs \\ %{}) when is_map(attrs) do
    case validate_attrs(attrs) do
      :ok ->
        budgets = struct(__MODULE__, attrs)
        {:ok, budgets}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Converts budgets to a map.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = budgets) do
    budgets
    |> Map.from_struct()
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc """
  Creates budgets from a map.
  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    struct(__MODULE__, map)
  end

  @doc """
  Validates budget constraints.
  """
  @spec validate(t()) :: :ok | {:error, term()}
  def validate(%__MODULE__{} = budgets) do
    budgets
    |> Map.from_struct()
    |> validate_attrs()
  end

  @doc """
  Checks if a request would exceed token budget.
  """
  @spec within_token_budget?(t(), integer()) :: boolean()
  def within_token_budget?(%__MODULE__{max_tokens_per_request: nil}, _tokens), do: true

  def within_token_budget?(%__MODULE__{max_tokens_per_request: max}, tokens) when tokens <= max,
    do: true

  def within_token_budget?(_, _), do: false

  @doc """
  Checks if a request would exceed cost budget.
  """
  @spec within_cost_budget?(t(), float()) :: boolean()
  def within_cost_budget?(%__MODULE__{max_cost_per_request: nil}, _cost), do: true
  def within_cost_budget?(%__MODULE__{max_cost_per_request: max}, cost) when cost <= max, do: true
  def within_cost_budget?(_, _), do: false

  @doc """
  Checks if any budget constraints are defined.
  """
  @spec has_constraints?(t()) :: boolean()
  def has_constraints?(%__MODULE__{} = budgets) do
    budgets
    |> Map.from_struct()
    |> Map.values()
    |> Enum.any?(&(not is_nil(&1)))
  end

  # Private helpers

  defp validate_attrs(attrs) do
    with :ok <- validate_positive_integer(attrs[:max_tokens_per_request], :max_tokens_per_request),
         :ok <- validate_positive_integer(attrs[:max_tokens_per_day], :max_tokens_per_day),
         :ok <- validate_positive_number(attrs[:max_cost_per_request], :max_cost_per_request),
         :ok <- validate_positive_number(attrs[:max_cost_per_day], :max_cost_per_day),
         :ok <-
           validate_positive_integer(attrs[:max_requests_per_minute], :max_requests_per_minute),
         :ok <- validate_positive_integer(attrs[:max_requests_per_hour], :max_requests_per_hour),
         :ok <- validate_positive_integer(attrs[:max_requests_per_day], :max_requests_per_day) do
      :ok
    end
  end

  defp validate_positive_integer(nil, _field), do: :ok
  defp validate_positive_integer(value, _field) when is_integer(value) and value > 0, do: :ok
  defp validate_positive_integer(_, field), do: {:error, {:invalid_budget_field, field}}

  defp validate_positive_number(nil, _field), do: :ok
  defp validate_positive_number(value, _field) when is_number(value) and value > 0, do: :ok
  defp validate_positive_number(_, field), do: {:error, {:invalid_budget_field, field}}
end
