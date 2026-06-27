defmodule DoneManager.TasksTest do
  use DoneManager.DataCase, async: true

  import DoneManager.HouseholdsFixtures
  import DoneManager.TasksFixtures

  alias DoneManager.Tasks

  describe "create_task/2" do
    test "creates the task and eagerly generates its current occurrence" do
      scope = owner_scope_fixture()

      assert {:ok, task} = Tasks.create_task(scope, %{"name" => "Spot breakfast"})
      assert task.name == "Spot breakfast"
      assert task.household_id == scope.household.id

      occurrence = Tasks.current_occurrence(task)
      assert occurrence
      refute Tasks.done?(occurrence)
    end

    test "requires a name" do
      scope = owner_scope_fixture()
      assert {:error, changeset} = Tasks.create_task(scope, %{"name" => ""})
      assert "can't be blank" in errors_on(changeset).name
    end
  end

  describe "household isolation (default-deny)" do
    test "list_tasks only returns the scope household's tasks" do
      owner = owner_scope_fixture()
      task_fixture(owner)
      _other = task_fixture(owner_scope_fixture())

      assert [task] = Tasks.list_tasks(owner)
      assert task.household_id == owner.household.id
    end

    test "get_task! raises for a task in another household" do
      owner = owner_scope_fixture()
      task = task_fixture(owner)
      stranger = owner_scope_fixture()

      assert_raise Ecto.NoResultsError, fn -> Tasks.get_task!(stranger, task.id) end
    end
  end

  describe "attempt_completion/2" do
    test "completes an open occurrence, then records a duplicate without undoing" do
      scope = owner_scope_fixture()
      task = task_fixture(scope)
      occurrence = Tasks.current_occurrence(task)

      assert {:completed, _event} =
               Tasks.attempt_completion(occurrence, %{source: "web", user_id: scope.user.id})

      assert Tasks.done?(occurrence)

      assert {:duplicate_completion_attempted, _event} =
               Tasks.attempt_completion(occurrence, %{source: "web", user_id: scope.user.id})

      # Still done — a duplicate attempt does not undo completion.
      assert Tasks.done?(occurrence)
    end
  end
end
