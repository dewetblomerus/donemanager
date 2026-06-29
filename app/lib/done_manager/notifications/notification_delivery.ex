defmodule DoneManager.Notifications.NotificationDelivery do
  @moduledoc """
  Current-state record of notifications sent for one occurrence to one recipient
  of one type. There is exactly one row per `(task_occurrence_id, user_id,
  notification_type)`; each send upserts it (bumping `reminder_count`, stamping
  `last_sent_at`/`last_status`) rather than appending. Gating reminder cadence
  and per-recipient quiet hours reads this row. See architecture/scheduling.md.

  `notification_type` is `"reminder"` today; `"completed"` is reserved for the
  later silent done-confirmation.
  """

  use DoneManager.Schema
  import Ecto.Changeset

  alias DoneManager.Accounts.User
  alias DoneManager.Tasks.TaskOccurrence

  schema "notification_deliveries" do
    field :notification_type, :string
    field :last_sent_at, :utc_datetime_usec
    field :reminder_count, :integer, default: 0
    field :last_status, :string

    belongs_to :task_occurrence, TaskOccurrence
    belongs_to :user, User

    timestamps()
  end

  @doc false
  def changeset(delivery, attrs) do
    delivery
    |> cast(attrs, [
      :task_occurrence_id,
      :user_id,
      :notification_type,
      :last_sent_at,
      :reminder_count,
      :last_status
    ])
    |> validate_required([:task_occurrence_id, :user_id, :notification_type])
    |> unique_constraint([:task_occurrence_id, :user_id, :notification_type],
      name: :notification_deliveries_occurrence_user_type_index
    )
  end
end
