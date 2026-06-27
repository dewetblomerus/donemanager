defmodule DoneManager.Repo.Migrations.CreateTasks do
  use Ecto.Migration

  def change do
    create table(:tasks) do
      add :household_id, references(:households, type: :uuid, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :description, :string
      add :task_type, :string, null: false, default: "scheduled"
      add :cadence_frequency, :string
      add :cadence_weekdays, {:array, :string}, null: false, default: []
      add :cadence_interval_minutes, :integer
      add :due_time, :time
      add :expiration_time, :time
      add :reminder_interval_minutes, :integer
      add :active, :boolean, null: false, default: true

      timestamps()
    end

    create index(:tasks, [:household_id])
  end
end
