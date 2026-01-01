defmodule AgentCore.Llm.Plan.Definition do
  @moduledoc """
  First-class, versioned Plan artifact (core).

  - Immutable artifact (no run state)
  - Serializable (to_map/from_map)
  - Structural validation only (no runtime module loading)
  """

  @enforce_keys [:id, :version, :steps]
  defstruct [
    :id,
    :version,
    :name,
    :description,
    :metadata,
    :policies,
    :steps,
    :checksum
  ]

  @type id :: String.t()
  @type version :: non_neg_integer()
  @type step_ref :: module() | String.t()
  @type policies :: map()
  @type metadata :: map()

  @type t :: %__MODULE__{
          id: id(),
          version: version(),
          name: String.t() | nil,
          description: String.t() | nil,
          metadata: metadata(),
          policies: policies(),
          steps: [step_ref()],
          checksum: String.t() | nil
        }

  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      id: Map.fetch!(attrs, :id),
      version: Map.fetch!(attrs, :version),
      name: Map.get(attrs, :name),
      description: Map.get(attrs, :description),
      metadata: Map.get(attrs, :metadata, %{}),
      policies: Map.get(attrs, :policies, %{}),
      steps: Map.fetch!(attrs, :steps),
      checksum: Map.get(attrs, :checksum)
    }
  end

  @doc "Structural validation only."
  def validate(%__MODULE__{} = plan) do
    errors =
      []
      |> require_string(:id, plan.id)
      |> require_int(:version, plan.version)
      |> validate_steps(plan.steps)
      |> validate_map(:policies, plan.policies)
      |> validate_map(:metadata, plan.metadata)

    if errors == [], do: {:ok, plan}, else: {:error, Enum.reverse(errors)}
  end

  def to_map(%__MODULE__{} = plan) do
    %{
      "id" => plan.id,
      "version" => plan.version,
      "name" => plan.name,
      "description" => plan.description,
      "metadata" => plan.metadata || %{},
      "policies" => plan.policies || %{},
      "steps" => Enum.map(plan.steps, &step_to_string/1),
      "checksum" => plan.checksum
    }
  end

  def from_map(%{} = m) do
    plan =
      new(%{
        id: pick(m, "id", :id),
        version: pick(m, "version", :version),
        name: pick(m, "name", :name),
        description: pick(m, "description", :description),
        metadata: pick(m, "metadata", :metadata) || %{},
        policies: pick(m, "policies", :policies) || %{},
        steps: Enum.map(pick(m, "steps", :steps) || [], &step_from_storage/1),
        checksum: pick(m, "checksum", :checksum)
      })

    validate(plan)
  rescue
    e in KeyError -> {:error, [{:plan, {:missing_key, e.key}}]}
  end

  # --- private helpers ---

  defp pick(m, k1, k2), do: Map.get(m, k1) || Map.get(m, k2)

  defp require_string(errors, field, value) do
    cond do
      not is_binary(value) -> [{field, :not_a_string} | errors]
      String.trim(value) == "" -> [{field, :blank} | errors]
      true -> errors
    end
  end

  defp require_int(errors, field, value) do
    if is_integer(value) and value >= 0,
      do: errors,
      else: [{field, :not_a_nonneg_integer} | errors]
  end

  defp validate_map(errors, field, value) do
    if is_map(value), do: errors, else: [{field, :not_a_map} | errors]
  end

  defp validate_steps(errors, steps) do
    cond do
      not is_list(steps) ->
        [{:steps, :not_a_list} | errors]

      steps == [] ->
        [{:steps, :empty} | errors]

      true ->
        Enum.reduce(Enum.with_index(steps), errors, fn {step, idx}, acc ->
          cond do
            is_atom(step) -> acc
            is_binary(step) and String.trim(step) != "" -> acc
            is_binary(step) -> [{:steps, {:blank_string, idx}} | acc]
            true -> [{:steps, {:invalid_step_ref, idx, step}} | acc]
          end
        end)
    end
  end

  defp step_to_string(step) when is_atom(step), do: Atom.to_string(step)
  defp step_to_string(step) when is_binary(step), do: step

  # Stored steps are strings; we keep them as strings in the artifact.
  # Runtime will resolve them to modules when executing.
  defp step_from_storage(step) when is_binary(step), do: String.trim(step)
  defp step_from_storage(step) when is_atom(step), do: Atom.to_string(step)
  defp step_from_storage(step), do: step
end
