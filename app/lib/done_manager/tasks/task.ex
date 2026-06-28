defmodule DoneManager.Tasks.Task do
  @moduledoc """
  A household chore definition: its name, behavior `task_type`, and cadence.

  `task_type` has no default — a creator must choose one deliberately, since the
  type decides which cadence fields apply. Validation is conditional on the
  chosen type, mirroring the per-type column ownership in architecture/database.md.

  In the Stage 2 slice a task is created with one eagerly-generated occurrence;
  recurrence generation (`scheduled`/`interval`) arrives with the reconcile loop.
  """

  use DoneManager.Schema
  import Ecto.Changeset

  alias DoneManager.Households.Household
  alias DoneManager.Tasks.TaskOccurrence

  @task_types ~w(scheduled interval timer)
  @weekdays ~w(mo tu we th fr sa su)

  schema "tasks" do
    field :name, :string
    field :description, :string
    field :task_type, :string
    field :cadence_weekdays, {:array, :string}, default: []
    field :cadence_interval_minutes, :integer
    field :due_time, :time
    field :expiration_time, :time
    field :valid_from, :time
    field :timer_minutes, :integer
    field :reminder_interval_minutes, :integer
    field :active, :boolean, default: true

    belongs_to :household, Household
    has_many :occurrences, TaskOccurrence

    timestamps()
  end

  @doc false
  def changeset(task, attrs) do
    task
    |> cast(normalize_times(attrs), [
      :name,
      :description,
      :task_type,
      :cadence_weekdays,
      :cadence_interval_minutes,
      :due_time,
      :expiration_time,
      :valid_from,
      :timer_minutes,
      :reminder_interval_minutes,
      :active
    ])
    |> validate_required([:name, :task_type])
    |> validate_inclusion(:task_type, @task_types)
    |> validate_number(:cadence_interval_minutes, greater_than: 0)
    |> validate_number(:timer_minutes, greater_than: 0)
    |> validate_number(:reminder_interval_minutes, greater_than: 0)
    |> validate_by_type()
  end

  # Each type owns its own cadence columns (see architecture/database.md). Clear
  # the fields that don't apply, then require the ones that do, so a stored task
  # can't carry contradictory cadence for its type.
  defp validate_by_type(changeset) do
    case get_field(changeset, :task_type) do
      "scheduled" ->
        changeset
        |> clear_fields([:cadence_interval_minutes, :timer_minutes])
        # A scheduled task must expire so a missed slot resolves and the next
        # one is generated (see architecture/database.md).
        |> validate_required([:due_time, :expiration_time])
        |> validate_subset(:cadence_weekdays, @weekdays)

      "interval" ->
        changeset
        |> clear_fields([:due_time, :expiration_time, :timer_minutes])
        |> put_change(:cadence_weekdays, [])
        |> validate_required([:cadence_interval_minutes])

      "timer" ->
        changeset
        |> clear_fields([
          :cadence_interval_minutes,
          :due_time,
          :expiration_time
        ])
        |> put_change(:cadence_weekdays, [])
        |> validate_required([:timer_minutes])

      _ ->
        changeset
    end
  end

  defp clear_fields(changeset, fields),
    do: Enum.reduce(fields, changeset, &put_change(&2, &1, nil))

  # HTML <input type="time"> submits "HH:MM"; Ecto's :time cast wants seconds.
  defp normalize_times(attrs) when is_map(attrs) do
    Enum.reduce(
      ["due_time", "expiration_time", "valid_from"],
      attrs,
      fn key, acc ->
        case Map.get(acc, key) do
          <<h::binary-size(2), ":", m::binary-size(2)>> -> Map.put(acc, key, "#{h}:#{m}:00")
          _ -> acc
        end
      end
    )
  end

  defp normalize_times(attrs), do: attrs

  def task_types, do: @task_types
  def weekdays, do: @weekdays
end
