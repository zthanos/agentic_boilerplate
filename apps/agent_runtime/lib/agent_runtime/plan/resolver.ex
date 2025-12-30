defmodule AgentRuntime.Llm.Plan.Resolver do
  @moduledoc "Resolves step refs to runtime modules and validates step contracts."

  alias AgentCore.Llm.Plan.Definition

  @type resolved_step :: module()

  @spec resolve_steps(Definition.t()) ::
          {:ok, [resolved_step()]} | {:error, list()}
  def resolve_steps(%Definition{} = plan) do
    errors =
      plan.steps
      |> Enum.with_index()
      |> Enum.reduce([], fn {ref, idx}, acc ->
        case resolve_step(ref) do
          {:ok, mod} ->
            case validate_step_module(mod) do
              :ok -> acc
              {:error, reason} -> [{:steps, {:invalid_step_module, idx, mod, reason}} | acc]
            end

          {:error, reason} ->
            [{:steps, {:unresolvable_step, idx, ref, reason}} | acc]
        end
      end)

    if errors == [] do
      {:ok, Enum.map(plan.steps, fn ref -> {:ok, mod} = resolve_step(ref); mod end)}
    else
      {:error, Enum.reverse(errors)}
    end
  end

  defp resolve_step(mod) when is_atom(mod) do
    if Code.ensure_loaded?(mod), do: {:ok, mod}, else: {:error, :unloaded}
  end

  defp resolve_step(str) when is_binary(str) do
    s = String.trim(str)

    cond do
      s == "" ->
        {:error, :blank}

      true ->
        mod =
          if String.starts_with?(s, "Elixir.") do
            String.to_atom(s)
          else
            String.to_atom("Elixir." <> s)
          end

        if Code.ensure_loaded?(mod), do: {:ok, mod}, else: {:error, :unloaded}
    end
  end

  defp resolve_step(other), do: {:error, {:invalid_ref_type, other}}

  defp validate_step_module(mod) do
    cond do
      not function_exported?(mod, :name, 0) -> {:error, :missing_name_0}
      not function_exported?(mod, :run, 2) -> {:error, :missing_run_2}
      true -> :ok
    end
  end
end
