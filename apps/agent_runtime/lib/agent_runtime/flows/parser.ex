defmodule AgentRuntime.Flows.Requirements.Parser do
  @moduledoc false

  alias AgentRuntime.Flows.Requirements.Schema
  alias ExJsonSchema.Schema, as: JSchema
  alias ExJsonSchema.Validator

  @compiled_schema JSchema.resolve(Schema.schema())

  @spec parse_and_validate(binary()) :: {:ok, map()} | {:error, term()}
  def parse_and_validate(text) when is_binary(text) do
    with {:ok, json} <- Jason.decode(text),
         :ok <- validate(json) do
      {:ok, json}
    else
      {:error, %Jason.DecodeError{} = e} ->
        {:error, {:invalid_json, e.data}}

      {:error, errors} when is_list(errors) ->
        {:error, {:schema_mismatch, errors}}

      other ->
        {:error, other}
    end
  end

  defp validate(json) when is_map(json) do
    case Validator.validate(@compiled_schema, json) do
      :ok -> :ok
      {:error, errors} -> {:error, errors}
    end
  end
end
