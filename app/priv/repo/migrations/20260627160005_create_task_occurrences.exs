defmodule DoneManager.Repo.Migrations.CreateTaskOccurrences do
  use Ecto.Migration

  def change do
    create table(:task_occurrences) do
      add :task_id, references(:tasks, type: :uuid, on_delete: :delete_all), null: false
      add :completed_by_id, references(:users, type: :uuid, on_delete: :nilify_all)
      add :due_at, :timestamptz, null: false
      add :expires_at, :timestamptz
      add :completed_at, :timestamptz

      timestamps()
    end

    create index(:task_occurrences, [:task_id])

    # Generation idempotency: "one open occurrence, create next on resolve" is
    # backed by uniqueness on (task_id, due_at) so two reconcile runs (or an
    # edit racing the loop) can't insert the same next occurrence twice.
    create unique_index(:task_occurrences, [:task_id, :due_at])
  end
end
