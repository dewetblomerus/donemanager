defmodule DoneManager.Repo.Migrations.CreateTasks do
  use Ecto.Migration

  def change do
    create table(:tasks) do
      add :household_id, references(:households, type: :uuid, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :description, :string
      add :task_type, :string, null: false
      add :cadence_weekdays, {:array, :string}, null: false, default: []
      add :cadence_interval_minutes, :integer
      add :due_time, :time
      add :expiration_time, :time
      # Earliest time of day a link tap may act on the task. The window end is
      # `expiration_time` (shared with occurrence resolution); null = all day.
      add :valid_from, :time
      add :timer_minutes, :integer
      add :reminder_interval_minutes, :integer
      add :active, :boolean, null: false, default: true

      timestamps()
    end

    create index(:tasks, [:household_id])
  end
end
