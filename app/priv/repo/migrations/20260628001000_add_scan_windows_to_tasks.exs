defmodule DoneManager.Repo.Migrations.AddScanWindowsToTasks do
  use Ecto.Migration

  def change do
    alter table(:tasks) do
      add :scan_window_start_time, :time
      add :scan_window_end_time, :time
    end

    create constraint(:tasks, :tasks_scan_window_pair_required,
             check:
               "(scan_window_start_time IS NULL AND scan_window_end_time IS NULL) OR (scan_window_start_time IS NOT NULL AND scan_window_end_time IS NOT NULL)"
           )

    create constraint(:tasks, :tasks_scan_window_not_empty,
             check:
               "scan_window_start_time IS NULL OR scan_window_end_time IS NULL OR scan_window_start_time <> scan_window_end_time"
           )

    drop_if_exists index(:automation_commands, [:nfc_tag_id],
                     where: "active",
                     name: :automation_commands_active_tag_unique
                   )

    drop_if_exists index(:automation_commands, [],
                     name: :automation_commands_active_tag_task_window_unique
                   )

    # A task has one active tag binding, but a tag can be shared by multiple
    # tasks. Scan resolution filters the linked tasks by their task-level scan
    # window and picks the first open occurrence by due time.
    create unique_index(:automation_commands, [:task_id],
             where: "active",
             name: :automation_commands_active_task_unique
           )
  end
end
