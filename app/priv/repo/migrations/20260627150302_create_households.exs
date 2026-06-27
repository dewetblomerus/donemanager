defmodule DoneManager.Repo.Migrations.CreateHouseholds do
  use Ecto.Migration

  def change do
    create table(:households) do
      add :name, :string, null: false
      add :timezone, :string, null: false

      timestamps()
    end
  end
end
