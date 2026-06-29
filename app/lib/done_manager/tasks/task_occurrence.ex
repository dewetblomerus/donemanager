defmodule DoneManager.Tasks.TaskOccurrence do
  @moduledoc """
  One concrete expected instance of a task, such as `Spot breakfast for
  2026-06-25`.

  Completion is stored on the row (`completed_at`, `completed_by_id`); expiry is
  derived from `expires_at`. An occurrence is *resolved* when it is completed or
  past its `expires_at`, which is what the generation loop keys on. See
  architecture/database.md and architecture/scheduling.md.
  """

  use DoneManager.Schema
  import Ecto.Changeset

  alias DoneManager.Accounts.User
  alias DoneManager.Tasks.Task

  schema "task_occurrences" do
    field :due_at, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec

    belongs_to :task, Task
    belongs_to :completed_by, User

    timestamps()
  end

  @doc false
  def changeset(occurrence, attrs) do
    occurrence
    |> cast(attrs, [:due_at, :expires_at, :completed_at, :completed_by_id])
    |> validate_required([:due_at])
  end

  @weekday_tokens %{1 => "mo", 2 => "tu", 3 => "we", 4 => "th", 5 => "fr", 6 => "sa", 7 => "su"}

  @doc """
  Derives `due_at`/`expires_at` for a task's next open occurrence, computed in the
  household `timezone`. See architecture/scheduling.md.

    * `scheduled` — the next `due_time` slot honoring `cadence_weekdays`
      (empty = every day): today if `due_time` is still ahead of now *and* today is
      an allowed weekday, otherwise the next allowed weekday. `expires_at` follows
      the midnight-crossing rule — the same local date as `due_at` when
      `expiration_time > due_time`, otherwise the next date.
    * `interval`/`timer` — due now, no expiry. The brand-new bootstrap is an open
      question (see scheduling.md), so this keeps the prior eager behavior.
  """
  def schedule_attrs(task, timezone, now \\ DateTime.utc_now())

  def schedule_attrs(%Task{task_type: "scheduled"} = task, timezone, now) do
    due_date = next_due_date(task, to_local(now, timezone))

    %{
      due_at: local_instant(due_date, task.due_time, timezone),
      expires_at: local_instant(expires_date(task, due_date), task.expiration_time, timezone)
    }
  end

  def schedule_attrs(%Task{}, _timezone, now), do: %{due_at: ensure_usec(now), expires_at: nil}

  @doc """
  Derives the next occurrence after a resolved occurrence.

  `scheduled` tasks use the next wall-clock slot after `now`; `interval` tasks
  are due `interval_minutes` after the completed occurrence.
  """
  def next_schedule_attrs(task, timezone, occurrence, now \\ DateTime.utc_now())

  def next_schedule_attrs(
        %Task{task_type: "interval", interval_minutes: minutes},
        _timezone,
        %__MODULE__{completed_at: %DateTime{} = completed_at},
        _now
      ) do
    %{due_at: completed_at |> DateTime.add(minutes, :minute) |> ensure_usec(), expires_at: nil}
  end

  def next_schedule_attrs(%Task{} = task, timezone, _occurrence, now),
    do: schedule_attrs(task, timezone, now)

  defp next_due_date(task, %DateTime{} = local_now) do
    today = DateTime.to_date(local_now)

    if allowed_weekday?(task, today) and
         Time.compare(task.due_time, DateTime.to_time(local_now)) == :gt do
      today
    else
      next_allowed_date(task, Date.add(today, 1))
    end
  end

  defp next_allowed_date(task, date) do
    if allowed_weekday?(task, date), do: date, else: next_allowed_date(task, Date.add(date, 1))
  end

  defp allowed_weekday?(%Task{cadence_weekdays: []}, _date), do: true

  defp allowed_weekday?(%Task{cadence_weekdays: days}, date),
    do: @weekday_tokens[Date.day_of_week(date)] in days

  # The slot expires later the same local day, unless expiration is at/before
  # due_time, in which case the window crosses midnight onto the next date.
  defp expires_date(%Task{expiration_time: exp, due_time: due}, due_date),
    do: if(Time.compare(exp, due) == :gt, do: due_date, else: Date.add(due_date, 1))

  defp to_local(%DateTime{} = utc, timezone) do
    case DateTime.shift_zone(utc, timezone) do
      {:ok, local} -> local
      {:error, _} -> utc
    end
  end

  defp local_instant(date, time, timezone) do
    date
    |> new_local(time, timezone)
    |> DateTime.shift_zone!("Etc/UTC")
    |> ensure_usec()
  end

  # A DST gap has no such wall-clock time; take the instant just after it. An
  # ambiguous (fall-back) time happens twice; take the first.
  defp new_local(date, time, timezone) do
    case DateTime.new(date, time, timezone) do
      {:ok, dt} -> dt
      {:ambiguous, first, _second} -> first
      {:gap, _just_before, just_after} -> just_after
      {:error, _} -> DateTime.new!(date, time, "Etc/UTC")
    end
  end

  # utc_datetime_usec requires microsecond precision; a Time without one yields {0, 0}.
  defp ensure_usec(%DateTime{microsecond: {value, _}} = dt), do: %{dt | microsecond: {value, 6}}

  @doc "Whether the occurrence has been completed."
  def done?(%__MODULE__{completed_at: nil}), do: false
  def done?(%__MODULE__{}), do: true

  @doc "Whether the occurrence is resolved — completed or past its expiry."
  def resolved?(occurrence, now \\ DateTime.utc_now())
  def resolved?(%__MODULE__{completed_at: %DateTime{}}, _now), do: true
  def resolved?(%__MODULE__{expires_at: nil}, _now), do: false

  def resolved?(%__MODULE__{expires_at: expires_at}, now),
    do: DateTime.compare(expires_at, now) != :gt
end
