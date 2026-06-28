defmodule DoneManager.Repo.Migrations.CreateLinkTasks do
  use Ecto.Migration

  def change do
    create table(:link_tasks) do
      add :household_id, references(:households, type: :uuid, on_delete: :delete_all), null: false
      add :link_id, references(:links, type: :uuid, on_delete: :delete_all), null: false
      add :task_id, references(:tasks, type: :uuid, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:link_tasks, [:household_id])
    create index(:link_tasks, [:task_id])
    create index(:link_tasks, [:link_id])

    # A link drives a task at most once; the bare join is the binding's identity.
    create unique_index(:link_tasks, [:link_id, :task_id])
  end
end
