defmodule DoneManager.TasksTest do
  use DoneManager.DataCase, async: true

  import DoneManager.HouseholdsFixtures
  import DoneManager.TasksFixtures

  alias DoneManager.Tasks

  describe "create_task/2" do
    test "creates the task and eagerly generates its current occurrence" do
      scope = owner_scope_fixture()

      assert {:ok, task} =
               Tasks.create_task(scope, %{
                 "name" => "Spot breakfast",
                 "task_type" => "scheduled",
                 "cadence_frequency" => "daily",
                 "due_time" => "11:00:00"
               })

      assert task.name == "Spot breakfast"
      assert task.household_id == scope.household.id

      occurrence = Tasks.current_occurrence(task)
      assert occurrence
      refute Tasks.done?(occurrence)
    end

    test "requires a name" do
      scope = owner_scope_fixture()
      assert {:error, changeset} = Tasks.create_task(scope, %{"task_type" => "one_off"})
      assert "can't be blank" in errors_on(changeset).name
    end

    test "requires an explicit task type (no default)" do
      scope = owner_scope_fixture()
      assert {:error, changeset} = Tasks.create_task(scope, %{"name" => "Mystery"})
      assert "can't be blank" in errors_on(changeset).task_type
    end
  end

  describe "create_task/2 conditional validation" do
    test "a scheduled task needs a frequency and due time" do
      scope = owner_scope_fixture()

      assert {:error, changeset} =
               Tasks.create_task(scope, %{"name" => "Feed", "task_type" => "scheduled"})

      assert "can't be blank" in errors_on(changeset).cadence_frequency
      assert "can't be blank" in errors_on(changeset).due_time
    end

    test "a weekly task needs at least one weekday" do
      scope = owner_scope_fixture()

      assert {:error, changeset} =
               Tasks.create_task(scope, %{
                 "name" => "Bins",
                 "task_type" => "scheduled",
                 "cadence_frequency" => "weekly",
                 "due_time" => "18:00:00"
               })

      assert errors_on(changeset).cadence_weekdays != []
    end

    test "an interval task needs an interval and ignores schedule fields" do
      scope = owner_scope_fixture()

      assert {:error, changeset} =
               Tasks.create_task(scope, %{"name" => "Dog out", "task_type" => "interval"})

      assert "can't be blank" in errors_on(changeset).cadence_interval_minutes

      assert {:ok, task} =
               Tasks.create_task(scope, %{
                 "name" => "Dog out",
                 "task_type" => "interval",
                 "cadence_interval_minutes" => "180",
                 "due_time" => "09:00:00"
               })

      assert task.cadence_interval_minutes == 180
      # Schedule-only fields are cleared for an interval task.
      assert task.due_time == nil
    end

    test "a one_off task needs timer minutes and carries no cadence" do
      scope = owner_scope_fixture()

      assert {:error, changeset} =
               Tasks.create_task(scope, %{"name" => "Laundry", "task_type" => "one_off"})

      assert "can't be blank" in errors_on(changeset).timer_minutes

      assert {:ok, task} =
               Tasks.create_task(scope, %{
                 "name" => "Laundry",
                 "task_type" => "one_off",
                 "timer_minutes" => "60"
               })

      assert task.timer_minutes == 60
      assert task.cadence_frequency == nil
      assert task.cadence_interval_minutes == nil
    end
  end

  describe "update_task/3" do
    test "updates a task in the scope's household" do
      scope = owner_scope_fixture()
      task = task_fixture(scope)

      assert {:ok, updated} =
               Tasks.update_task(scope, task, %{"name" => "Spot dinner", "due_time" => "18:00"})

      assert updated.name == "Spot dinner"
      assert updated.due_time == ~T[18:00:00]
    end

    test "rejects updating a task from another household" do
      owner = owner_scope_fixture()
      task = task_fixture(owner)
      other = owner_scope_fixture()

      assert {:error, :unauthorized} = Tasks.update_task(other, task, %{"name" => "Hijack"})
    end
  end

  describe "complete_via_web/2" do
    test "records a web completion attributed to the user, then reports duplicates" do
      scope = owner_scope_fixture()
      task = task_fixture(scope)

      assert {:ok, :completed} = Tasks.complete_via_web(scope, task)

      occurrence = Tasks.current_occurrence(task)
      assert Tasks.done?(occurrence)
      event = Tasks.completion_event(occurrence)
      assert event.source == "web"
      assert event.user_id == scope.user.id

      assert {:ok, :duplicate_completion_attempted} = Tasks.complete_via_web(scope, task)
      assert Tasks.done?(occurrence)
    end

    test "rejects a user not in the task's household" do
      owner = owner_scope_fixture()
      task = task_fixture(owner)
      other = owner_scope_fixture()

      assert {:error, :unauthorized} = Tasks.complete_via_web(other, task)
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
