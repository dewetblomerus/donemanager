defmodule DoneManager.LinksTest do
  use DoneManager.DataCase, async: true

  import DoneManager.HouseholdsFixtures
  import DoneManager.LinksFixtures
  import DoneManager.TasksFixtures

  alias DoneManager.Links

  describe "links and bindings" do
    test "create, list with tasks, and bind/unbind" do
      scope = owner_scope_fixture()
      task = task_fixture(scope)
      link = link_fixture(scope)

      assert {:ok, _binding} = Links.bind_task(scope, link, task.id)
      assert [task.id] == Links.list_tasks_for_link(link) |> Enum.map(& &1.id)

      [loaded] = Links.list_links_with_tasks(scope)
      assert [binding] = loaded.link_tasks
      assert {:ok, _} = Links.unbind_task(scope, binding.id)
      assert [] == Links.list_tasks_for_link(link)
    end

    test "binding the same task twice is idempotent" do
      scope = owner_scope_fixture()
      task = task_fixture(scope)
      link = link_fixture(scope)

      assert {:ok, binding} = Links.bind_task(scope, link, task.id)
      assert {:ok, ^binding} = Links.bind_task(scope, link, task.id)
      assert [task.id] == Links.list_tasks_for_link(link) |> Enum.map(& &1.id)
    end

    test "rejects binding a task from another household" do
      scope = owner_scope_fixture()
      other = owner_scope_fixture()
      task = task_fixture(other)
      link = link_fixture(scope)

      assert {:error, :not_found} = Links.bind_task(scope, link, task.id)
      assert [] == Links.list_tasks_for_link(link)
    end
  end

  describe "resolve_execute/3" do
    test "returns the current occurrence of a bound scheduled task" do
      scope = owner_scope_fixture()
      task = task_fixture(scope)
      link = link_fixture(scope)
      bind_fixture(scope, link, task)

      # 09:00 falls inside the default task's [valid_from 00:00, expiration 11:00) window.
      assert {:ok, occurrence} = Links.resolve_execute(scope, link.id, ~U[2026-06-28 09:00:00Z])
      assert occurrence.task_id == task.id
    end

    test "unassigned link returns :unassigned" do
      scope = owner_scope_fixture()
      link = link_fixture(scope)

      assert {:error, :unassigned} = Links.resolve_execute(scope, link.id)
    end

    test "returns the current occurrence of a bound timer task" do
      scope = owner_scope_fixture()
      task = task_fixture(scope, %{"task_type" => "timer", "interval_minutes" => 60})
      link = link_fixture(scope)
      bind_fixture(scope, link, task)

      assert {:ok, occurrence} = Links.resolve_execute(scope, link.id)
      assert occurrence.task_id == task.id
    end

    test "a non-member cannot resolve the link" do
      scope = owner_scope_fixture()
      task = task_fixture(scope)
      link = link_fixture(scope)
      bind_fixture(scope, link, task)

      stranger = owner_scope_fixture()
      assert {:error, :not_found} = Links.resolve_execute(stranger, link.id)
    end

    test "routes a multi-task link by execute window" do
      scope = owner_scope_fixture()

      breakfast =
        task_fixture(scope, %{
          "name" => "Dog breakfast",
          "due_time" => "08:00:00",
          "expiration_time" => "11:00:00",
          "valid_from" => "05:00"
        })

      dinner =
        task_fixture(scope, %{
          "name" => "Dog dinner",
          "due_time" => "18:00:00",
          "expiration_time" => "21:00:00",
          "valid_from" => "12:00"
        })

      link = link_fixture(scope)
      bind_fixture(scope, link, breakfast)
      bind_fixture(scope, link, dinner)

      morning = ~U[2026-06-28 07:00:00Z]
      evening = ~U[2026-06-28 19:00:00Z]

      assert {:ok, occ} = Links.resolve_execute(scope, link.id, morning)
      assert occ.task_id == breakfast.id

      assert {:ok, occ} = Links.resolve_execute(scope, link.id, evening)
      assert occ.task_id == dinner.id
    end

    test "returns previous and next occurrence context outside task execution hours" do
      scope = owner_scope_fixture()

      breakfast =
        task_fixture(scope, %{
          "name" => "Dog breakfast",
          "due_time" => "08:00:00",
          "expiration_time" => "11:00:00",
          "valid_from" => "05:00"
        })

      dinner =
        task_fixture(scope, %{
          "name" => "Dog dinner",
          "due_time" => "18:00:00",
          "expiration_time" => "21:00:00",
          "valid_from" => "17:00"
        })

      link = link_fixture(scope)
      bind_fixture(scope, link, breakfast)
      bind_fixture(scope, link, dinner)

      afternoon = ~U[2026-06-28 13:00:00Z]

      assert {:warning, context} = Links.resolve_execute(scope, link.id, afternoon)
      assert context.previous.task_id == breakfast.id
      assert context.previous.task.name == "Dog breakfast"
      assert context.next.task_id == dinner.id
      assert context.next.task.name == "Dog dinner"
    end
  end
end
