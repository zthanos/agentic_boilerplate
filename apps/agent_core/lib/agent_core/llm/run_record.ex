defmodule AgentCore.Llm.RunRecord do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:fingerprint, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]
  schema "llm_runs" do
    field :profile_id, :string
    field :profile_name, :string
    field :provider, :string
    field :model, :string
    field :policy_version, :string
    field :resolved_at, :utc_datetime_usec

    field :overrides, :map, default: %{}
    field :invocation_config, :map, default: %{}

    timestamps()
  end

  def changeset(rec, attrs) do
    rec
    |> cast(attrs, [
      :fingerprint,
      :profile_id,
      :profile_name,
      :provider,
      :model,
      :policy_version,
      :resolved_at,
      :overrides,
      :invocation_config
    ])
    |> validate_required([:fingerprint, :profile_id, :provider, :model, :policy_version, :resolved_at, :overrides, :invocation_config])
  end
end
