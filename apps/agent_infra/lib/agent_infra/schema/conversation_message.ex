defmodule AgentInfra.Schema.ConversationMessage do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "conversation_messages" do
    field(:conversation_id, Ecto.UUID)
    field(:role, :string)
    field(:content, :string)
    field(:metadata, :map, default: %{})
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [:id, :conversation_id, :role, :content, :metadata])
    |> validate_required([:id, :conversation_id, :role, :content])
    |> validate_inclusion(:role, ["user", "assistant", "system"])
  end
end
