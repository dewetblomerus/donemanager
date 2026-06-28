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
