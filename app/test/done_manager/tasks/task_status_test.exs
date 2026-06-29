defmodule DoneManager.Tasks.TaskStatusTest do
  use ExUnit.Case, async: true

  alias DoneManager.Tasks.Task
  alias DoneManager.Tasks.TaskOccurrence
  alias DoneManager.Tasks.TaskStatus

  defp scheduled(attrs \\ %{}) do
    struct!(
      %Task{
        task_type: "scheduled",
        cadence_weekdays: [],
        valid_from: ~T[14:00:00],
        due_time: ~T[14:00:00],
        expiration_time: ~T[18:00:00]
      },
      attrs
    )
  end

  defp completed_at(%DateTime{} = at), do: %TaskOccurrence{due_at: at, completed_at: at}

  defp state(task, last, now, tz \\ "Etc/UTC"),
    do: TaskStatus.derive(task, nil, last, tz, now).state

  describe "scheduled" do
    test "before the window reads not_yet" do
      assert state(scheduled(), nil, ~U[2026-06-29 10:00:00Z]) == :not_yet
    end

    test "inside the window reads open" do
      assert state(scheduled(), nil, ~U[2026-06-29 15:00:00Z]) == :open
    end

    test "after the window with no completion reads missed" do
      assert state(scheduled(), nil, ~U[2026-06-29 19:00:00Z]) == :missed
    end

    test "completed today reads done, and stays done after the window closes" do
      done = completed_at(~U[2026-06-29 15:00:00Z])
      assert state(scheduled(), done, ~U[2026-06-29 15:30:00Z]) == :done
      assert state(scheduled(), done, ~U[2026-06-29 19:00:00Z]) == :done
    end

    test "a completion from yesterday does not read done today — the bug" do
      yesterday = completed_at(~U[2026-06-28 15:00:00Z])

      # Morning, before the window: not_yet, never a stale Done.
      assert state(scheduled(), yesterday, ~U[2026-06-29 10:00:00Z]) == :not_yet
      # Inside today's window: open again.
      assert state(scheduled(), yesterday, ~U[2026-06-29 15:00:00Z]) == :open
    end

    test "a day the cadence excludes reads not_yet even inside the clock window" do
      # 2026-06-29 is a Monday; restrict to Tuesdays only.
      task = scheduled(%{cadence_weekdays: ["tu"]})
      assert state(task, nil, ~U[2026-06-29 15:00:00Z]) == :not_yet
    end

    test "done is keyed on the household-local date, not the UTC date" do
      tz = "America/New_York"
      # now is 2026-06-28 23:00 local; the completion is 2026-06-28 22:00 local.
      now = ~U[2026-06-29 03:00:00Z]
      same_local_day = completed_at(~U[2026-06-29 02:00:00Z])
      prior_local_day = completed_at(~U[2026-06-28 02:00:00Z])

      assert state(scheduled(), same_local_day, now, tz) == :done
      refute state(scheduled(), prior_local_day, now, tz) == :done
    end
  end

  describe "interval" do
    defp interval, do: %Task{task_type: "interval", interval_minutes: 180}

    defp interval_state(current, last, now),
      do: TaskStatus.derive(interval(), current, last, "Etc/UTC", now).state

    test "within the interval since a completion reads done" do
      current = %TaskOccurrence{due_at: ~U[2026-06-29 15:00:00Z]}
      last = completed_at(~U[2026-06-29 12:00:00Z])
      assert interval_state(current, last, ~U[2026-06-29 14:00:00Z]) == :done
    end

    test "past due reads overdue" do
      current = %TaskOccurrence{due_at: ~U[2026-06-29 12:00:00Z]}
      last = completed_at(~U[2026-06-29 09:00:00Z])
      assert interval_state(current, last, ~U[2026-06-29 15:00:00Z]) == :overdue
    end

    test "a brand-new task awaiting its first completion reads open" do
      current = %TaskOccurrence{due_at: ~U[2026-06-29 18:00:00Z]}
      assert interval_state(current, nil, ~U[2026-06-29 15:00:00Z]) == :open
    end
  end

  describe "timer" do
    defp timer, do: %Task{task_type: "timer", interval_minutes: 60}

    defp timer_state(current, now),
      do: TaskStatus.derive(timer(), current, nil, "Etc/UTC", now).state

    test "a countdown still ahead reads running" do
      current = %TaskOccurrence{due_at: ~U[2026-06-29 15:00:00Z]}
      assert timer_state(current, ~U[2026-06-29 14:30:00Z]) == :running
    end

    test "no active occurrence reads idle" do
      assert timer_state(nil, ~U[2026-06-29 14:30:00Z]) == :idle
    end

    test "an elapsed countdown reads idle" do
      current = %TaskOccurrence{due_at: ~U[2026-06-29 14:00:00Z]}
      assert timer_state(current, ~U[2026-06-29 14:30:00Z]) == :idle
    end
  end

  test "completable? allows web completion only before/within the window" do
    assert TaskStatus.completable?(%TaskStatus{state: :open})
    assert TaskStatus.completable?(%TaskStatus{state: :not_yet})
    assert TaskStatus.completable?(%TaskStatus{state: :overdue})
    refute TaskStatus.completable?(%TaskStatus{state: :done})
    refute TaskStatus.completable?(%TaskStatus{state: :missed})
  end
end
