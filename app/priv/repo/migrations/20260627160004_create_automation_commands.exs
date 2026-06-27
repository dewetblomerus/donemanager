defmodule DoneManager.Repo.Migrations.CreateAutomationCommands do
  use Ecto.Migration

  def change do
    create table(:automation_commands) do
      add :household_id, references(:households, type: :uuid, on_delete: :delete_all), null: false
      add :task_id, references(:tasks, type: :uuid, on_delete: :delete_all), null: false
      add :nfc_tag_id, references(:nfc_tags, type: :uuid, on_delete: :delete_all), null: false
      add :label, :string
      add :command_type, :string, null: false
      add :config, :map, null: false, default: %{}
      add :active, :boolean, null: false, default: true

      timestamps()
    end

    create index(:automation_commands, [:household_id])
    create index(:automation_commands, [:task_id])

    # One active command per tag resolves a scan unambiguously.
    create unique_index(:automation_commands, [:nfc_tag_id],
             where: "active",
             name: :automation_commands_active_tag_unique
           )
  end
end
