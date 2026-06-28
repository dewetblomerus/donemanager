defmodule DoneManager.Automation.AutomationCommand do
  @moduledoc """
  Links a tag to a task. A task has one active tag binding, while a tag can be
  shared by multiple tasks. Scan resolution filters linked tasks by their
  task-level scan windows and chooses the first open occurrence by due time. What
  a scan *does* (complete vs. toggle a timer) is derived from the task's type at
  scan time, not stored here. See architecture/database.md.
  """

  use DoneManager.Schema
  import Ecto.Changeset

  alias DoneManager.Automation.NfcTag
  alias DoneManager.Households.Household
  alias DoneManager.Tasks.Task

  schema "automation_commands" do
    field :label, :string
    field :active, :boolean, default: true

    belongs_to :household, Household
    belongs_to :task, Task
    belongs_to :nfc_tag, NfcTag

    timestamps()
  end

  @doc false
  def changeset(command, attrs) do
    command
    |> cast(attrs, [:label, :active])
    |> unique_constraint(:task_id,
      name: :automation_commands_active_task_unique,
      message: "task already has an active tag"
    )
  end
end
