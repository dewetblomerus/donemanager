defmodule DoneManager.Repo.Migrations.CreateLinks do
  use Ecto.Migration

  def change do
    create table(:links) do
      add :household_id, references(:households, type: :uuid, on_delete: :delete_all), null: false
      add :label, :string
      add :active, :boolean, null: false, default: true

      timestamps()
    end

    create index(:links, [:household_id])
  end
end
