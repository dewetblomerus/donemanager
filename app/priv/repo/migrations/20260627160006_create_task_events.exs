defmodule DoneManager.Repo.Migrations.CreateTaskEvents do
  use Ecto.Migration

  def change do
    create table(:task_events) do
      # Retention deletes old occurrences; their event log cascades with them.
      add :task_occurrence_id,
          references(:task_occurrences, type: :uuid, on_delete: :delete_all),
          null: false

      add :user_id, references(:users, type: :uuid, on_delete: :nilify_all)
      add :nfc_tag_id, references(:nfc_tags, type: :uuid, on_delete: :nilify_all)

      add :automation_command_id,
          references(:automation_commands, type: :uuid, on_delete: :nilify_all)

      add :integration_bearer_token_id,
          references(:integration_bearer_tokens, type: :uuid, on_delete: :nilify_all)

      add :event_type, :string, null: false
      add :source, :string, null: false
      add :occurred_at, :timestamptz, null: false

      timestamps(updated_at: false)
    end

    create index(:task_events, [:task_occurrence_id])
  end
end
