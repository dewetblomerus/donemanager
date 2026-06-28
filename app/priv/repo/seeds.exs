# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     DoneManager.Repo.insert!(%DoneManager.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

import Ecto.Query

alias DoneManager.Accounts.Scope
alias DoneManager.Households.Household
alias DoneManager.Repo
alias DoneManager.Tasks
alias DoneManager.Tasks.Task

household =
  Household
  |> order_by([h], desc: h.inserted_at)
  |> limit(1)
  |> Repo.one()

if is_nil(household) do
  raise "No household exists. Create a household locally before running seeds."
end

scope = Scope.put_household(%Scope{}, household)

med_tasks = [
  %{
    "name" => "Knox Morning Meds",
    "task_type" => "scheduled",
    "cadence_frequency" => "daily",
    "due_time" => "08:00:00",
    "expiration_time" => "12:00:00",
    "execute_window_start_time" => "08:00:00",
    "execute_window_end_time" => "12:00:00"
  },
  %{
    "name" => "Knox Afternoon Meds",
    "task_type" => "scheduled",
    "cadence_frequency" => "daily",
    "due_time" => "14:00:00",
    "expiration_time" => "18:00:00",
    "execute_window_start_time" => "14:00:00",
    "execute_window_end_time" => "18:00:00"
  },
  %{
    "name" => "Knox Nighttime Meds",
    "task_type" => "scheduled",
    "cadence_frequency" => "daily",
    "due_time" => "20:00:00",
    "expiration_time" => "23:59:00",
    "execute_window_start_time" => "20:00:00",
    "execute_window_end_time" => "23:59:00"
  }
]

Enum.each(med_tasks, fn attrs ->
  existing_task =
    Repo.get_by(Task,
      household_id: household.id,
      name: attrs["name"],
      task_type: attrs["task_type"]
    )

  if existing_task do
    {:ok, task} = Tasks.update_task(scope, existing_task, attrs)
    IO.puts("Updated #{task.name} in #{household.name}")
  else
    {:ok, task} = Tasks.create_task(scope, attrs)
    IO.puts("Seeded #{task.name} in #{household.name}")
  end
end)
