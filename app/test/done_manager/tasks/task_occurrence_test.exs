defmodule DoneManager.Tasks.TaskOccurrenceTest do
  use ExUnit.Case, async: true

  alias DoneManager.Tasks.Task
  alias DoneManager.Tasks.TaskOccurrence

  defp scheduled(attrs) do
    struct!(
      %Task{
        task_type: "scheduled",
        cadence_weekdays: [],
        due_time: ~T[08:00:00],
        expiration_time: ~T[11:00:00]
      },
      attrs
    )
  end

  defp eq?(%DateTime{} = a, %DateTime{} = b), do: DateTime.compare(a, b) == :eq

  describe "schedule_attrs/3 for scheduled tasks" do
    test "due_time still ahead today schedules today, expiring the same day" do
      attrs = TaskOccurrence.schedule_attrs(scheduled(%{}), "Etc/UTC", ~U[2026-06-28 06:00:00Z])

      assert eq?(attrs.due_at, ~U[2026-06-28 08:00:00Z])
      assert eq?(attrs.expires_at, ~U[2026-06-28 11:00:00Z])
    end

    test "due_time already passed today schedules the next day" do
      attrs = TaskOccurrence.schedule_attrs(scheduled(%{}), "Etc/UTC", ~U[2026-06-28 09:00:00Z])

      assert eq?(attrs.due_at, ~U[2026-06-29 08:00:00Z])
      assert eq?(attrs.expires_at, ~U[2026-06-29 11:00:00Z])
    end

    test "expiration at/before due_time crosses midnight onto the next date" do
      task = scheduled(%{due_time: ~T[22:00:00], expiration_time: ~T[02:00:00]})
      attrs = TaskOccurrence.schedule_attrs(task, "Etc/UTC", ~U[2026-06-28 06:00:00Z])

      assert eq?(attrs.due_at, ~U[2026-06-28 22:00:00Z])
      assert eq?(attrs.expires_at, ~U[2026-06-29 02:00:00Z])
    end

    test "restricts to the next allowed weekday" do
      task = scheduled(%{cadence_weekdays: ["tu"]})
      attrs = TaskOccurrence.schedule_attrs(task, "Etc/UTC", ~U[2026-06-28 06:00:00Z])

      # 2026-06-28 is a Sunday; the next Tuesday is 2026-06-30.
      assert Date.day_of_week(DateTime.to_date(attrs.due_at)) == 2
      assert eq?(attrs.due_at, ~U[2026-06-30 08:00:00Z])
    end

    test "computes the slot in the household timezone" do
      # 2026-06-27 22:00Z is 2026-06-28 07:00 JST; 08:00 JST is still ahead.
      attrs =
        TaskOccurrence.schedule_attrs(scheduled(%{}), "Asia/Tokyo", ~U[2026-06-27 22:00:00Z])

      assert eq?(attrs.due_at, ~U[2026-06-27 23:00:00Z])
      assert eq?(attrs.expires_at, ~U[2026-06-28 02:00:00Z])
    end
  end

  describe "schedule_attrs/3 for interval and timer tasks" do
    test "interval is due now with no expiry" do
      now = ~U[2026-06-28 06:00:00Z]
      task = %Task{task_type: "interval", interval_minutes: 180}

      assert TaskOccurrence.schedule_attrs(task, "Etc/UTC", now).expires_at == nil
      assert eq?(TaskOccurrence.schedule_attrs(task, "Etc/UTC", now).due_at, now)
    end

    test "timer is due now with no expiry" do
      now = ~U[2026-06-28 06:00:00Z]
      task = %Task{task_type: "timer", interval_minutes: 60}

      assert TaskOccurrence.schedule_attrs(task, "Etc/UTC", now).expires_at == nil
      assert eq?(TaskOccurrence.schedule_attrs(task, "Etc/UTC", now).due_at, now)
    end
  end
end
