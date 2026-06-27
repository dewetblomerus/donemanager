defmodule DoneManager.Tasks.Task do
  @moduledoc """
  A household chore definition: its name, behavior `task_type`, and cadence.

  In the Stage 2 slice a task is created with one eagerly-generated occurrence;
  recurrence generation (`scheduled`/`interval`) arrives with the reconcile loop.
  See architecture/database.md and architecture/stages.md.
  """

  use DoneManager.Schema
  import Ecto.Changeset

  alias DoneManager.Households.Household
  alias DoneManager.Tasks.TaskOccurrence

  @task_types ~w(scheduled interval one_off)

  schema "tasks" do
    field :name, :string
    field :description, :string
    field :task_type, :string, default: "scheduled"
    field :cadence_frequency, :string
    field :cadence_weekdays, {:array, :string}, default: []
    field :cadence_interval_minutes, :integer
    field :due_time, :time
    field :expiration_time, :time
    field :reminder_interval_minutes, :integer
    field :active, :boolean, default: true

    belongs_to :household, Household
    has_many :occurrences, TaskOccurrence

    timestamps()
  end

  @doc false
  def changeset(task, attrs) do
    task
    |> cast(attrs, [
      :name,
      :description,
      :task_type,
      :cadence_frequency,
      :cadence_weekdays,
      :cadence_interval_minutes,
      :due_time,
      :expiration_time,
      :reminder_interval_minutes,
      :active
    ])
    |> validate_required([:name, :task_type])
    |> validate_inclusion(:task_type, @task_types)
  end

  def task_types, do: @task_types
end
