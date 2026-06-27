defmodule DoneManager.Repo.Migrations.CreateTaskOccurrences do
  use Ecto.Migration

  def change do
    create table(:task_occurrences) do
      add :task_id, references(:tasks, type: :uuid, on_delete: :delete_all), null: false
      add :occurrence_date, :date
      add :due_at, :timestamptz, null: false
      add :expires_at, :timestamptz

      timestamps(updated_at: false)
    end

    create index(:task_occurrences, [:task_id])
  end
end
