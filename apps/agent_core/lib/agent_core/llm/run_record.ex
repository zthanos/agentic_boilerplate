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
    field :overrides, :map
    field :invocation_config, :map

    # v2 lifecycle
    field :status, :string, default: "created"
    field :started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec
    field :error, :map
    field :usage, :map
    field :latency_ms, :integer

    timestamps(type: :utc_datetime_usec)
  end


  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :fingerprint,
      :profile_id,
      :profile_name,
      :provider,
      :model,
      :policy_version,
      :resolved_at,
      :overrides,
      :invocation_config,
      # v2
      :status,
      :started_at,
      :finished_at,
      :error,
      :usage,
      :latency_ms
    ])
    |> validate_required([:fingerprint, :status])
  end
end
