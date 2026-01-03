defmodule AgentCore.Llm.Agent.Definition do
  @moduledoc """
  First-class, versioned Agent artifact.

  Agent packages:
  - plan binding (plan_id + plan_version)
  - profile binding (execution/assessor/embeddings profile ids)
  - prompts (system prompt string for now)
  - policies (agent-level defaults/overrides)
  """

  @derive Jason.Encoder
  @enforce_keys [:id, :version, :plan]
  defstruct [
    :id,
    :version,
    :name,
    :description,
    :metadata,
    :plan,
    :profiles,
    :prompts,
    :policies,
    :checksum
  ]

  @type id :: String.t()
  @type version :: non_neg_integer()

  @type plan_ref :: %{
          id: String.t(),
          version: non_neg_integer() | :latest
        }

  @type profiles :: %{
          optional(:execution_profile_id) => String.t(),
          optional(:assessor_profile_id) => String.t(),
          optional(:embeddings_profile_id) => String.t()
        }

  @type prompts :: %{
          optional(:system) => String.t()
        }

  @type t :: %__MODULE__{
          id: id(),
          version: version(),
          name: String.t() | nil,
          description: String.t() | nil,
          metadata: map(),
          plan: plan_ref(),
          profiles: profiles(),
          prompts: prompts(),
          policies: map(),
          checksum: String.t() | nil
        }

  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      id: Map.fetch!(attrs, :id),
      version: Map.fetch!(attrs, :version),
      name: Map.get(attrs, :name),
      description: Map.get(attrs, :description),
      metadata: Map.get(attrs, :metadata, %{}),
      plan: Map.fetch!(attrs, :plan),
      profiles: Map.get(attrs, :profiles, %{}),
      prompts: Map.get(attrs, :prompts, %{}),
      policies: Map.get(attrs, :policies, %{}),
      checksum: Map.get(attrs, :checksum)
    }
  end

  @doc "Structural validation only."
  def validate(%__MODULE__{} = agent) do
    errors =
      []
      |> require_string(:id, agent.id)
      |> require_int(:version, agent.version)
      |> validate_plan(agent.plan)
      |> validate_map(:metadata, agent.metadata)
      |> validate_map(:profiles, agent.profiles)
      |> validate_map(:prompts, agent.prompts)
      |> validate_map(:policies, agent.policies)
      |> validate_system_prompt(agent.prompts)

    if errors == [], do: {:ok, agent}, else: {:error, Enum.reverse(errors)}
  end

  def to_map(%__MODULE__{} = a) do
    %{
      "id" => a.id,
      "version" => a.version,
      "name" => a.name,
      "description" => a.description,
      "metadata" => a.metadata || %{},
      "plan" => a.plan,
      "profiles" => a.profiles || %{},
      "prompts" => a.prompts || %{},
      "policies" => a.policies || %{},
      "checksum" => a.checksum
    }
  end

  def from_map(%{} = m) do
    agent =
      new(%{
        id: m["id"] || m[:id],
        version: m["version"] || m[:version],
        name: m["name"] || m[:name],
        description: m["description"] || m[:description],
        metadata: m["metadata"] || m[:metadata] || %{},
        plan: m["plan"] || m[:plan],
        profiles: m["profiles"] || m[:profiles] || %{},
        prompts: m["prompts"] || m[:prompts] || %{},
        policies: m["policies"] || m[:policies] || %{},
        checksum: m["checksum"] || m[:checksum]
      })

    validate(agent)
  rescue
    e in KeyError -> {:error, [{:agent, {:missing_key, e.key}}]}
  end

  # ---- helpers ----

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

  defp validate_plan(errors, plan) when is_map(plan) do
    id = plan["id"] || plan[:id]
    ver = plan["version"] || plan[:version]

    errors
    |> require_string(:plan_id, id)
    |> validate_plan_version(ver)
  end

  defp validate_plan(errors, _), do: [{:plan, :not_a_map} | errors]

  defp validate_plan_version(errors, :latest), do: errors

  defp validate_plan_version(errors, v) do
    if is_integer(v) and v >= 0, do: errors, else: [{:plan_version, :invalid} | errors]
  end

  defp validate_system_prompt(errors, prompts) do
    sys = prompts["system"] || prompts[:system]

    cond do
      is_nil(sys) -> errors
      not is_binary(sys) -> [{:system_prompt, :not_a_string} | errors]
      String.trim(sys) == "" -> [{:system_prompt, :blank} | errors]
      true -> errors
    end
  end
end
