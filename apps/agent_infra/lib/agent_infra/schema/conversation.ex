defmodule AgentInfra.Schema.Conversation do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "conversations" do
    field(:user_id, :string)
    field(:title, :string)
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [:id, :user_id, :title])
    |> validate_required([:id, :user_id])
  end
end
