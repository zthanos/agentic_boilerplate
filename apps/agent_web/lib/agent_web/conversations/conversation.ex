defmodule AgentWeb.Conversations.Conversation do
  use Ecto.Schema

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "conversations" do
    field :user_id, :string
    field :title, :string
    timestamps(type: :utc_datetime_usec)
  end
end
