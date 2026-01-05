defmodule AgentInfra.Schema.Profile do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, []}
  schema "llm_profiles" do
    field(:name, :string)
    field(:enabled, :boolean, default: true)

    field(:provider_id, :string)
    field(:model, :string)
    field(:policy_version, :string)

    field(:generation, :map, default: %{})
    field(:budgets, :map, default: %{})
    field(:tools, {:array, :string}, default: [])
    field(:stop_list, {:array, :string}, default: [])
    field(:tags, {:array, :string}, default: [])

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :id,
      :name,
      :enabled,
      :provider_id,
      :model,
      :policy_version,
      :generation,
      :budgets,
      :tools,
      :stop_list,
      :tags
    ])
    |> validate_required([:id, :provider_id, :model, :enabled])
  end
end
