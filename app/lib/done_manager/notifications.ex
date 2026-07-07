defmodule DoneManager.Notifications do
  @moduledoc """
  The reconcile loop's "Remind" step: push a reminder to a household when a task
  is due/overdue, until it is completed. This is also what makes `timer` tasks
  work — a timer past its `due_at` is just an open, overdue occurrence.

  Recipients are all members of the task's household who have a Pushover key.
  Per-recipient cadence and quiet-hours gating read the `notification_deliveries`
  row for `(occurrence, user, "reminder")`, which each send upserts in place.
  Quiet hours soften delivery (Pushover priority -1), they do not suppress it.
  See architecture/scheduling.md.
  """

  import Ecto.Query, warn: false
  require Logger

  alias DoneManager.Accounts.User
  alias DoneManager.Households.HouseholdMembership
  alias DoneManager.Notifications.NotificationDelivery
  alias DoneManager.Pushover
  alias DoneManager.Repo
  alias DoneManager.Tasks.Task
  alias DoneManager.Tasks.TaskOccurrence

  @type_reminder "reminder"

  @doc """
  Sends reminders for every open, overdue occurrence. Idempotent per tick: a
  recipient already reminded within `tasks.reminder_interval_minutes` is skipped
  (and a null interval means a single reminder).
  """
  def send_due_reminders(now \\ DateTime.utc_now()) do
    now
    |> due_occurrences()
    |> Enum.each(&remind_occurrence(&1, now))

    :ok
  end

  # Open (not completed), not expired, and past due — across all task types, so
  # timers re-enter here even though the generation loop skips them.
  defp due_occurrences(now) do
    from(o in TaskOccurrence,
      join: t in Task,
      on: t.id == o.task_id,
      where:
        t.active and is_nil(o.completed_at) and o.due_at <= ^now and
          (is_nil(o.expires_at) or o.expires_at > ^now),
      preload: [task: :household]
    )
    |> Repo.all()
  end

  defp remind_occurrence(%TaskOccurrence{task: %Task{} = task} = occurrence, now) do
    for user <- recipients(task.household_id) do
      delivery = get_delivery(occurrence.id, user.id)

      if due_to_send?(delivery, task.reminder_interval_minutes, now) do
        send_reminder(occurrence, task, user, delivery, now)
      end
    end
  end

  defp recipients(household_id) do
    from(m in HouseholdMembership,
      join: u in User,
      on: u.id == m.user_id,
      where: m.household_id == ^household_id and not is_nil(u.pushover_user_key),
      select: u
    )
    |> Repo.all()
  end

  defp get_delivery(occurrence_id, user_id) do
    Repo.get_by(NotificationDelivery,
      task_occurrence_id: occurrence_id,
      user_id: user_id,
      notification_type: @type_reminder
    )
  end

  # No row yet -> first reminder. Null interval -> single reminder (a row means
  # done). Otherwise re-send once the interval has elapsed since the last send.
  defp due_to_send?(nil, _interval, _now), do: true
  defp due_to_send?(%NotificationDelivery{}, nil, _now), do: false

  defp due_to_send?(%NotificationDelivery{last_sent_at: last}, interval, now),
    do: DateTime.diff(now, last, :minute) >= interval

  defp send_reminder(occurrence, task, user, delivery, now) do
    priority = if quiet_hours?(user, task.household.timezone, now), do: -1

    status =
      case Pushover.send_message(user.pushover_user_key, "#{task.name} is due.",
             title: task.name,
             priority: priority,
             url: occurrence_execute_url(occurrence),
             url_title: "Mark done"
           ) do
        :ok ->
          "ok"

        {:error, reason} ->
          Logger.error("Reminder send failed for occurrence #{occurrence.id}: #{inspect(reason)}")
          "error"
      end

    upsert_delivery(occurrence.id, user.id, delivery, status, now)
  end

  # Deep-links the reminder to this exact occurrence's execute action, so tapping
  # it acts on the notified occurrence rather than a freshly-generated one.
  defp occurrence_execute_url(occurrence) do
    DoneManagerWeb.Endpoint.url() <> "/occurrences/#{occurrence.id}/execute"
  end

  defp upsert_delivery(occurrence_id, user_id, delivery, status, now) do
    count = if delivery, do: delivery.reminder_count, else: 0

    %NotificationDelivery{}
    |> NotificationDelivery.changeset(%{
      task_occurrence_id: occurrence_id,
      user_id: user_id,
      notification_type: @type_reminder,
      last_sent_at: now,
      reminder_count: count + 1,
      last_status: status
    })
    |> Repo.insert(
      on_conflict: {:replace, [:last_sent_at, :reminder_count, :last_status, :updated_at]},
      conflict_target: [:task_occurrence_id, :user_id, :notification_type]
    )
  end

  # Quiet hours are per-user wall-clock times in the household timezone. Either
  # bound missing means no quiet hours. The window is start-inclusive,
  # end-exclusive and may cross midnight (start > finish).
  defp quiet_hours?(%User{quiet_hours_start: start, quiet_hours_end: finish}, timezone, now)
       when not is_nil(start) and not is_nil(finish) do
    time = now |> to_local(timezone) |> DateTime.to_time()

    case Time.compare(start, finish) do
      :lt -> after_or_at?(time, start) and Time.compare(time, finish) == :lt
      :gt -> after_or_at?(time, start) or Time.compare(time, finish) == :lt
      :eq -> false
    end
  end

  defp quiet_hours?(_user, _timezone, _now), do: false

  defp after_or_at?(time, mark), do: Time.compare(time, mark) != :lt

  defp to_local(%DateTime{} = utc, timezone) do
    case DateTime.shift_zone(utc, timezone) do
      {:ok, local} -> local
      {:error, _} -> utc
    end
  end
end
