defmodule AgentWeb.Conversations.ConversationMessage do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "conversation_messages" do
    field :conversation_id, Ecto.UUID
    field :role, :string
    field :content, :string
    field :run_id, Ecto.UUID
    field :seq, :integer
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(msg, attrs) do
    msg
    |> cast(attrs, [:id, :conversation_id, :role, :content, :run_id, :seq])
    |> validate_required([:id, :conversation_id, :role, :content, :seq])
  end
end
