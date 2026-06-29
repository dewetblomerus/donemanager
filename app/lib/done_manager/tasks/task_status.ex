defmodule DoneManager.Tasks.TaskStatus do
  @moduledoc """
  Derives a task's *display status* for the household-local "now" — the status
  the task list and task page show.

  It tracks the clock, not just the newest occurrence: a fixed-schedule chore
  done yesterday reads "Not yet" again this morning, never a stale "Done". This
  is a pure function of the task's schedule fields, its current and last-completed
  occurrences, the household timezone, and `now` — it stores nothing. See
  architecture/flows.md and architecture/scheduling.md.

  "Done" is keyed on a completion *today* (household-local date) and is held for
  the rest of the local day, resetting at midnight — the decided boundary.
  """

  alias DoneManager.Tasks.Task
  alias DoneManager.Tasks.TaskOccurrence

  @weekday_tokens %{1 => "mo", 2 => "tu", 3 => "we", 4 => "th", 5 => "fr", 6 => "sa", 7 => "su"}
  @midnight ~T[00:00:00]

  @type state :: :not_yet | :open | :overdue | :done | :missed | :running | :idle

  @enforce_keys [:state]
  defstruct [:state, :occurrence, :last_completion]

  @doc """
  Derives the display status from a task, its current (newest) occurrence, its
  most recent completed occurrence, the household `timezone`, and `now`.
  """
  def derive(task, current, last_completion, timezone, now \\ DateTime.utc_now())

  def derive(%Task{task_type: "scheduled"} = task, current, last, timezone, now) do
    struct(scheduled_state(task, last, timezone, now), current, last)
  end

  def derive(%Task{task_type: "interval"}, current, last, _timezone, now) do
    struct(interval_state(current, last, now), current, last)
  end

  def derive(%Task{task_type: "timer"}, current, _last, _timezone, now) do
    struct(timer_state(current, now), current, nil)
  end

  defp struct(state, current, last),
    do: %__MODULE__{state: state, occurrence: current, last_completion: last}

  @doc "Human label for a status state."
  def label(:not_yet), do: "Not yet"
  def label(:open), do: "Open"
  def label(:overdue), do: "Overdue"
  def label(:done), do: "Done"
  def label(:missed), do: "Missed"
  def label(:running), do: "Running"
  def label(:idle), do: "Idle"

  @doc "daisyUI badge modifier for a status state."
  def badge_class(:done), do: "badge-success"
  def badge_class(:overdue), do: "badge-error"
  def badge_class(:missed), do: "badge-error"
  def badge_class(:open), do: "badge-info"
  def badge_class(:running), do: "badge-info"
  def badge_class(_state), do: "badge-ghost"

  @doc "Whether the task can be completed from the web in this state."
  def completable?(%__MODULE__{state: state}), do: state in [:not_yet, :open, :overdue]

  # Scheduled: keyed on today's window and a completion today, in household time.
  defp scheduled_state(task, last, timezone, now) do
    local = to_local(now, timezone)
    today = DateTime.to_date(local)
    now_time = DateTime.to_time(local)

    cond do
      completed_today?(last, today, timezone) -> :done
      not allowed_weekday?(task, today) -> :not_yet
      window_contains?(task.valid_from, task.expiration_time, now_time) -> :open
      Time.compare(now_time, task.valid_from || @midnight) == :lt -> :not_yet
      true -> :missed
    end
  end

  # Interval: due relative to the last completion; "Done" until due again, then
  # grows overdue. No window, never "missed".
  defp interval_state(nil, _last, _now), do: :open
  defp interval_state(%TaskOccurrence{completed_at: %DateTime{}}, _last, _now), do: :done

  defp interval_state(%TaskOccurrence{due_at: due_at}, last, now) do
    cond do
      DateTime.compare(now, due_at) != :lt -> :overdue
      is_nil(last) -> :open
      true -> :done
    end
  end

  # Timer: running while an uncompleted occurrence's countdown is still ahead.
  defp timer_state(nil, _now), do: :idle
  defp timer_state(%TaskOccurrence{completed_at: %DateTime{}}, _now), do: :idle

  defp timer_state(%TaskOccurrence{due_at: due_at}, now),
    do: if(DateTime.compare(due_at, now) == :gt, do: :running, else: :idle)

  defp completed_today?(
         %TaskOccurrence{completed_at: %DateTime{} = completed_at},
         today,
         timezone
       ),
       do: DateTime.to_date(to_local(completed_at, timezone)) == today

  defp completed_today?(_last, _today, _timezone), do: false

  defp allowed_weekday?(%Task{cadence_weekdays: []}, _date), do: true

  defp allowed_weekday?(%Task{cadence_weekdays: days}, date),
    do: @weekday_tokens[Date.day_of_week(date)] in days

  # [valid_from, expiration_time): start-inclusive, end-exclusive, crossing
  # midnight when expiration is at or before valid_from. Mirrors the execute
  # window in DoneManager.Links.
  defp window_contains?(from, until, time) do
    from = from || @midnight

    cond do
      is_nil(until) ->
        Time.compare(time, from) != :lt

      Time.compare(from, until) == :lt ->
        after_or_at?(time, from) and Time.compare(time, until) == :lt

      true ->
        after_or_at?(time, from) or Time.compare(time, until) == :lt
    end
  end

  defp after_or_at?(time, mark), do: Time.compare(time, mark) != :lt

  defp to_local(%DateTime{} = utc, timezone) do
    case DateTime.shift_zone(utc, timezone) do
      {:ok, local} -> local
      {:error, _} -> utc
    end
  end
end
