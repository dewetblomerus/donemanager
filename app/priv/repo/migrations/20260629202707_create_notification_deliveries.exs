defmodule DoneManager.Repo.Migrations.CreateNotificationDeliveries do
  use Ecto.Migration

  def change do
    create table(:notification_deliveries) do
      add :task_occurrence_id,
          references(:task_occurrences, on_delete: :delete_all, type: :uuid),
          null: false

      add :user_id, references(:users, on_delete: :delete_all, type: :uuid), null: false
      add :notification_type, :string, null: false
      add :last_sent_at, :utc_datetime_usec
      add :reminder_count, :integer, null: false, default: 0
      add :last_status, :string

      timestamps()
    end

    create unique_index(
             :notification_deliveries,
             [:task_occurrence_id, :user_id, :notification_type],
             name: :notification_deliveries_occurrence_user_type_index
           )
  end
end
