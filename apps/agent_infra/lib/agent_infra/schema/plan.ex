defmodule AgentInfra.Schema.Plan do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "llm_plans" do
    field(:plan_id, :string)
    field(:version, :integer)
    field(:status, :string, default: "active")
    field(:checksum, :string)
    field(:definition, :map)

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [:plan_id, :version, :status, :checksum, :definition])
    |> validate_required([:plan_id, :version, :status, :definition])
    |> unique_constraint([:plan_id, :version])
  end
end
