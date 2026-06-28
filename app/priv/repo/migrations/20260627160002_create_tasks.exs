defmodule DoneManager.Repo.Migrations.CreateTasks do
  use Ecto.Migration

  def change do
    create table(:tasks) do
      add :household_id, references(:households, type: :uuid, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :description, :string
      add :task_type, :string, null: false
      add :cadence_frequency, :string
      add :cadence_weekdays, {:array, :string}, null: false, default: []
      add :cadence_interval_minutes, :integer
      add :due_time, :time
      add :expiration_time, :time
      add :execute_window_start_time, :time
      add :execute_window_end_time, :time
      add :timer_minutes, :integer
      add :reminder_interval_minutes, :integer
      add :active, :boolean, null: false, default: true

      timestamps()
    end

    create index(:tasks, [:household_id])

    # The execute window (when a link tap may act on the task) is a nullable
    # pair: both set or both null, and never an empty range.
    create constraint(:tasks, :tasks_execute_window_pair_required,
             check:
               "(execute_window_start_time IS NULL AND execute_window_end_time IS NULL) OR (execute_window_start_time IS NOT NULL AND execute_window_end_time IS NOT NULL)"
           )

    create constraint(:tasks, :tasks_execute_window_not_empty,
             check:
               "execute_window_start_time IS NULL OR execute_window_end_time IS NULL OR execute_window_start_time <> execute_window_end_time"
           )
  end
end
