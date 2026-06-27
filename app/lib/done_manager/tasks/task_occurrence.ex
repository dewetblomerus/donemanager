defmodule DoneManager.Tasks.TaskOccurrence do
  @moduledoc """
  One concrete expected instance of a task, such as `Spot breakfast for
  2026-06-25`. Status is never stored here — it is derived from related
  `task_events`. See architecture/database.md.
  """

  use DoneManager.Schema
  import Ecto.Changeset

  alias DoneManager.Tasks.Task
  alias DoneManager.Tasks.TaskEvent

  schema "task_occurrences" do
    field :occurrence_date, :date
    field :due_at, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec

    belongs_to :task, Task
    has_many :events, TaskEvent

    timestamps(updated_at: false)
  end

  @doc false
  def changeset(occurrence, attrs) do
    occurrence
    |> cast(attrs, [:occurrence_date, :due_at, :expires_at])
    |> validate_required([:due_at])
  end
end
