defmodule DoneManager.Repo.Migrations.CreateHouseholdMemberships do
  use Ecto.Migration

  def change do
    create table(:household_memberships) do
      add :household_id, references(:households, type: :uuid, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :role, :string, null: false

      timestamps()
    end

    create index(:household_memberships, [:household_id])
    create index(:household_memberships, [:user_id])
    create unique_index(:household_memberships, [:household_id, :user_id])
  end
end
