defmodule DoneManager.Repo.Migrations.CreateNfcTags do
  use Ecto.Migration

  def change do
    create table(:nfc_tags) do
      add :household_id, references(:households, type: :uuid, on_delete: :delete_all), null: false
      add :label, :string
      add :external_id, :string, null: false
      add :active, :boolean, null: false, default: true
      add :last_scanned_at, :timestamptz

      timestamps()
    end

    create unique_index(:nfc_tags, [:household_id, :external_id])
  end
end
