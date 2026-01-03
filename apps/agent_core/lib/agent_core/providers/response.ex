defmodule AgentCore.Providers.Response do
  @moduledoc """
  Domain model for LLM provider responses.

  Represents a standardized response from any LLM provider.
  Provider implementations transform provider-specific responses into this format.
  """

  defstruct [
    :id,
    :model,
    :choices,
    :usage,
    :created_at,
    :finish_reason,
    :metadata
  ]

  @type choice :: %{
          index: integer(),
          message: message(),
          finish_reason: finish_reason() | nil
        }

  @type message :: %{
          role: :assistant | :tool,
          content: String.t() | nil,
          tool_calls: [tool_call()] | nil,
          name: String.t() | nil
        }

  @type tool_call :: %{
          id: String.t(),
          type: String.t(),
          function: %{
            name: String.t(),
            arguments: String.t()
          }
        }

  @type usage :: %{
          prompt_tokens: integer(),
          completion_tokens: integer(),
          total_tokens: integer(),
          cost: float() | nil
        }

  @type finish_reason :: :stop | :length | :tool_calls | :content_filter | :error

  @type t :: %__MODULE__{
          id: String.t() | nil,
          model: String.t() | nil,
          choices: [choice()],
          usage: usage() | nil,
          created_at: DateTime.t() | nil,
          finish_reason: finish_reason() | nil,
          metadata: map() | nil
        }

  @doc """
  Creates a successful response with the given content.
  """
  @spec success(String.t(), keyword()) :: t()
  def success(content, opts \\ []) do
    choice = %{
      index: 0,
      message: %{
        role: :assistant,
        content: content
      },
      finish_reason: Keyword.get(opts, :finish_reason, :stop)
    }

    %__MODULE__{
      choices: [choice],
      usage: Keyword.get(opts, :usage),
      finish_reason: Keyword.get(opts, :finish_reason, :stop),
      metadata: %{
        raw: Keyword.get(opts, :raw)
      }
    }
  end

  @doc """
  Creates a new provider response.

  ## Examples

      iex> AgentCore.Providers.Response.new(
      ...>   choices: [%{
      ...>     index: 0,
      ...>     message: %{role: :assistant, content: "Hello!"},
      ...>     finish_reason: :stop
      ...>   }]
      ...> )
      {:ok, %AgentCore.Providers.Response{...}}
  """
  @spec new(keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs \\ []) when is_list(attrs) do
    attrs_map =
      attrs
      |> Map.new()
      |> Map.put_new(:choices, [])
      |> Map.put_new(:metadata, %{})

    case validate_response_attrs(attrs_map) do
      :ok ->
        response = struct(__MODULE__, attrs_map)
        {:ok, response}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Validates a provider response.
  """
  @spec validate(t()) :: :ok | {:error, term()}
  def validate(%__MODULE__{} = response) do
    response
    |> Map.from_struct()
    |> validate_response_attrs()
  end

  @doc """
  Gets the primary response content (first choice).
  """
  @spec content(t()) :: String.t() | nil
  def content(%__MODULE__{choices: []}), do: nil
  def content(%__MODULE__{choices: [%{message: %{content: content}} | _]}), do: content

  @doc """
  Gets all tool calls from the response.
  """
  @spec tool_calls(t()) :: [tool_call()]
  def tool_calls(%__MODULE__{choices: choices}) do
    choices
    |> Enum.flat_map(fn %{message: message} ->
      Map.get(message, :tool_calls, [])
    end)
  end

  @doc """
  Checks if the response contains tool calls.
  """
  @spec has_tool_calls?(t()) :: boolean()
  def has_tool_calls?(%__MODULE__{} = response) do
    length(tool_calls(response)) > 0
  end

  @doc """
  Gets the finish reason for the response.
  """
  @spec finish_reason(t()) :: finish_reason() | nil
  def finish_reason(%__MODULE__{finish_reason: reason}) when not is_nil(reason), do: reason
  def finish_reason(%__MODULE__{choices: []}), do: nil
  def finish_reason(%__MODULE__{choices: [%{finish_reason: reason} | _]}), do: reason

  @doc """
  Checks if the response finished successfully.
  """
  @spec finished_successfully?(t()) :: boolean()
  def finished_successfully?(%__MODULE__{} = response) do
    case finish_reason(response) do
      :stop -> true
      :tool_calls -> true
      _ -> false
    end
  end

  @doc """
  Gets token usage information.
  """
  @spec usage(t()) :: usage() | nil
  def usage(%__MODULE__{usage: usage}), do: usage

  @doc """
  Gets the total token count.
  """
  @spec total_tokens(t()) :: integer() | nil
  def total_tokens(%__MODULE__{usage: nil}), do: nil
  def total_tokens(%__MODULE__{usage: %{total_tokens: total}}), do: total

  @doc """
  Gets the estimated cost of the response.
  """
  @spec cost(t()) :: float() | nil
  def cost(%__MODULE__{usage: nil}), do: nil
  def cost(%__MODULE__{usage: %{cost: cost}}), do: cost

  @doc """
  Converts the response to a simple text representation.
  """
  @spec to_text(t()) :: String.t()
  def to_text(%__MODULE__{} = response) do
    case content(response) do
      nil -> ""
      text -> text
    end
  end

  @doc """
  Merges multiple responses (useful for streaming).
  """
  @spec merge([t()]) :: t()
  def merge([]), do: %__MODULE__{}
  def merge([response]), do: response

  def merge([first | rest]) do
    Enum.reduce(rest, first, &merge_two/2)
  end

  # Private helpers

  defp validate_response_attrs(attrs) do
    with :ok <- validate_choices(attrs[:choices]),
         :ok <- validate_usage(attrs[:usage]),
         :ok <- validate_finish_reason(attrs[:finish_reason]) do
      :ok
    end
  end

  defp validate_choices(nil), do: :ok
  defp validate_choices([]), do: :ok

  defp validate_choices(choices) when is_list(choices) do
    if Enum.all?(choices, &valid_choice?/1) do
      :ok
    else
      {:error, :invalid_choices}
    end
  end

  defp validate_choices(_), do: {:error, :invalid_choices}

  defp validate_usage(nil), do: :ok
  defp validate_usage(%{total_tokens: total}) when is_integer(total) and total >= 0, do: :ok
  defp validate_usage(_), do: {:error, :invalid_usage}

  defp validate_finish_reason(nil), do: :ok

  defp validate_finish_reason(reason)
       when reason in [:stop, :length, :tool_calls, :content_filter, :error], do: :ok

  defp validate_finish_reason(_), do: {:error, :invalid_finish_reason}

  defp valid_choice?(%{index: index, message: message})
       when is_integer(index) and is_map(message), do: valid_message?(message)

  defp valid_choice?(_), do: false

  defp valid_message?(%{role: role}) when role in [:assistant, :tool], do: true
  defp valid_message?(_), do: false

  defp merge_two(response1, response2) do
    %__MODULE__{
      id: response2.id || response1.id,
      model: response2.model || response1.model,
      choices: merge_choices(response1.choices, response2.choices),
      usage: merge_usage(response1.usage, response2.usage),
      created_at: response2.created_at || response1.created_at,
      finish_reason: response2.finish_reason || response1.finish_reason,
      metadata: Map.merge(response1.metadata || %{}, response2.metadata || %{})
    }
  end

  defp merge_choices(choices1, choices2) do
    # Simple merge - in practice this would be more sophisticated
    choices2 ++ choices1
  end

  defp merge_usage(nil, usage2), do: usage2
  defp merge_usage(usage1, nil), do: usage1

  defp merge_usage(usage1, usage2) do
    %{
      prompt_tokens: usage2.prompt_tokens || usage1.prompt_tokens,
      completion_tokens: (usage1.completion_tokens || 0) + (usage2.completion_tokens || 0),
      total_tokens: (usage1.total_tokens || 0) + (usage2.total_tokens || 0),
      cost: add_costs(usage1.cost, usage2.cost)
    }
  end

  defp add_costs(nil, cost2), do: cost2
  defp add_costs(cost1, nil), do: cost1
  defp add_costs(cost1, cost2), do: cost1 + cost2
end
