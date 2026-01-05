defmodule AgentWeb.Repo.Migrations.RenameProviderToProviderIdInLlmProfiles do
  use Ecto.Migration

  def up do
    # Rename the provider column to provider_id
    rename table(:llm_profiles), :provider, to: :provider_id

    # Drop the old index on provider
    drop index(:llm_profiles, [:provider])

    # Create new index on provider_id
    create index(:llm_profiles, [:provider_id])
  end

  def down do
    # Rename back from provider_id to provider
    rename table(:llm_profiles), :provider_id, to: :provider

    # Drop the new index on provider_id
    drop index(:llm_profiles, [:provider_id])

    # Recreate the old index on provider
    create index(:llm_profiles, [:provider])
  end
end
