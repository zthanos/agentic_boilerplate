defmodule AgentInfra.Repo.Migrations.EnableVector do
  use Ecto.Migration

  def change do
    execute("CREATE EXTENSION IF NOT EXISTS vector", "DROP EXTENSION IF EXISTS vector")
  end
end
