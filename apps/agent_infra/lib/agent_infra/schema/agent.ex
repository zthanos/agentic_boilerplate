defmodule AgentInfra.Schema.Agent do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "llm_agents" do
    field(:agent_id, :string)
    field(:version, :integer)
    field(:status, :string, default: "active")
    field(:checksum, :string)
    field(:definition, :map)

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [:agent_id, :version, :status, :checksum, :definition])
    |> validate_required([:agent_id, :version, :status, :definition])
    |> unique_constraint([:agent_id, :version])
  end
end
