defmodule DoneManager.Repo.Migrations.CreateIntegrationBearerTokens do
  use Ecto.Migration

  def change do
    create table(:integration_bearer_tokens) do
      add :household_id, references(:households, type: :uuid, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :uuid, on_delete: :nilify_all)
      add :created_by_user_id, references(:users, type: :uuid, on_delete: :nilify_all)
      add :label, :string
      add :prefix, :string, null: false
      add :token_hash, :string, null: false
      add :source, :string
      add :revoked_at, :timestamptz
      add :last_used_at, :timestamptz

      timestamps()
    end

    create unique_index(:integration_bearer_tokens, [:prefix])
    create index(:integration_bearer_tokens, [:household_id])
  end
end
