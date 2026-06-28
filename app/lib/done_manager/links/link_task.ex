defmodule DoneManager.Links.LinkTask do
  @moduledoc """
  A bare join binding one `link` to a `task` — `(household_id, link_id,
  task_id)`. A link may drive multiple tasks, and a task may be reachable from
  multiple links. To stop a link driving a task, delete the row.

  What an execute *does* (complete vs. toggle a timer) is derived from the
  task's type at execute time, not stored here. See architecture/database.md.
  """

  use DoneManager.Schema
  import Ecto.Changeset

  alias DoneManager.Households.Household
  alias DoneManager.Links.Link
  alias DoneManager.Tasks.Task

  schema "link_tasks" do
    belongs_to :household, Household
    belongs_to :link, Link
    belongs_to :task, Task

    timestamps()
  end

  @doc false
  def changeset(link_task, attrs) do
    link_task
    |> cast(attrs, [:link_id, :task_id])
    |> unique_constraint([:link_id, :task_id],
      message: "this link is already bound to this task"
    )
  end
end
