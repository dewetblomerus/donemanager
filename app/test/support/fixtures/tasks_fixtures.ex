defmodule DoneManager.TasksFixtures do
  @moduledoc "Test fixtures for the Tasks context."

  alias DoneManager.Accounts.Scope
  alias DoneManager.Tasks

  @doc "Creates a task (with its eager occurrence) in the scope's household."
  def task_fixture(%Scope{} = scope, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        "name" => "Spot breakfast",
        "task_type" => "scheduled",
        "cadence_frequency" => "daily",
        "due_time" => "11:00:00"
      })

    {:ok, task} = Tasks.create_task(scope, attrs)
    task
  end
end
