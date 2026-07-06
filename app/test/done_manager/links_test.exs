defmodule DoneManager.LinksTest do
  use DoneManager.DataCase, async: true

  import Ecto.Query
  import ExUnit.CaptureLog
  import DoneManager.HouseholdsFixtures
  import DoneManager.LinksFixtures
  import DoneManager.TasksFixtures

  alias DoneManager.Links
  alias DoneManager.Repo
  alias DoneManager.Tasks
  alias DoneManager.Tasks.TaskOccurrence

  # task_fixture seeds its eager occurrence at the real clock; pin it onto a
  # chosen day so date-aware execute windows are deterministic.
  defp bootstrap_on(task, %DateTime{} = at) do
    Repo.delete_all(from(o in TaskOccurrence, where: o.task_id == ^task.id))
    Tasks.reconcile_occurrences(at)
    task
  end

  defp utc(date, time), do: DateTime.new!(date, time, "Etc/UTC")

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
      task = task_fixture(scope) |> bootstrap_on(utc(~D[2026-06-28], ~T[06:00:00]))
      link = link_fixture(scope)
      bind_fixture(scope, link, task)

      # 09:00 falls inside the default task's [valid_from 00:00, expiration 11:00) window.
      assert {:ok, occurrence} =
               Links.resolve_execute(scope, link.id, utc(~D[2026-06-28], ~T[09:00:00]))

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

      # Pin both occurrences onto the same day so date-aware windows are stable.
      dawn = utc(~D[2026-06-28], ~T[04:00:00])
      bootstrap_on(breakfast, dawn)
      bootstrap_on(dinner, dawn)

      morning = ~U[2026-06-28 07:00:00Z]
      evening = ~U[2026-06-28 19:00:00Z]

      assert {:ok, occ} = Links.resolve_execute(scope, link.id, morning)
      assert occ.task_id == breakfast.id

      assert {:ok, occ} = Links.resolve_execute(scope, link.id, evening)
      assert occ.task_id == dinner.id
    end

    test "a second tap the same evening does not reach tomorrow's occurrence" do
      # Regression: a task whose execute window extends past due_time (and across
      # midnight) would, after tonight's completion, let a further tap inside the
      # same window complete tomorrow's freshly-generated occurrence a day early —
      # which then read "already done" at tomorrow's real dinner.
      scope = owner_scope_fixture()

      task =
        task_fixture(scope, %{
          "name" => "Dog dinner",
          "due_time" => "21:00:00",
          "expiration_time" => "01:00:00",
          "valid_from" => "17:00:00"
        })

      link = link_fixture(scope)
      bind_fixture(scope, link, task)
      bootstrap_on(task, utc(~D[2026-06-28], ~T[12:00:00]))

      # Tonight's tap completes tonight's occurrence; the loop then opens tomorrow's.
      first = utc(~D[2026-06-28], ~T[21:13:00])
      assert {:ok, tonight} = Links.resolve_execute(scope, link.id, first)
      assert {:completed, _} = Tasks.complete_occurrence(tonight, scope.user.id)
      Tasks.reconcile_occurrences(first)

      # A second tap 10 minutes later is still inside 17:00-01:00: it surfaces
      # tonight's already-done occurrence (UI reads "already done"), never
      # tomorrow's freshly-generated one.
      second = utc(~D[2026-06-28], ~T[21:23:00])
      assert {:ok, still_tonight} = Links.resolve_execute(scope, link.id, second)
      assert still_tonight.id == tonight.id
      refute is_nil(still_tonight.completed_at)

      # Tomorrow's dinner remains open and completable.
      tomorrow_dinner = utc(~D[2026-06-29], ~T[21:05:00])
      assert {:ok, occ} = Links.resolve_execute(scope, link.id, tomorrow_dinner)
      assert is_nil(occ.completed_at)
      assert DateTime.to_date(DateTime.shift_zone!(occ.due_at, "Etc/UTC")) == ~D[2026-06-29]
    end

    test "a re-tap after tonight's dinner is done shows tonight's dinner, not breakfast" do
      # Regression: the dogfood tag drives both breakfast and dinner. Once tonight's
      # dinner is completed the reconcile loop opens *tomorrow's* dinner occurrence,
      # which occurrence_started?/4 rightly drops (its window opens tomorrow). The
      # tap then fell through to the outside-hours context, whose nearest-window
      # math picked *breakfast* (window ended ~9h ago) over dinner (cross-midnight
      # ~19h) — so a re-tap during dinner showed the breakfast UI instead of
      # "already done" for the dinner your partner just handled.
      scope = owner_scope_fixture()

      breakfast =
        task_fixture(scope, %{
          "name" => "Dog breakfast",
          "due_time" => "08:00:00",
          "expiration_time" => "11:00:00",
          "valid_from" => "05:00:00"
        })

      dinner =
        task_fixture(scope, %{
          "name" => "Dog dinner",
          "due_time" => "21:00:00",
          "expiration_time" => "01:00:00",
          "valid_from" => "17:00:00"
        })

      link = link_fixture(scope)
      bind_fixture(scope, link, breakfast)
      bind_fixture(scope, link, dinner)

      dawn = utc(~D[2026-06-28], ~T[04:00:00])
      bootstrap_on(breakfast, dawn)
      bootstrap_on(dinner, dawn)

      # Your partner completes tonight's dinner at 20:39, before the 21:00 due —
      # so the next slot still collides with tonight's and no roll-forward happens.
      first = utc(~D[2026-06-28], ~T[20:39:00])
      assert {:ok, tonight} = Links.resolve_execute(scope, link.id, first)
      assert tonight.task_id == dinner.id
      assert {:completed, _} = Tasks.complete_occurrence(tonight, scope.user.id)

      # After 21:00 a reconcile tick opens *tomorrow's* dinner (current occurrence
      # is now tomorrow's), which occurrence_started?/4 rightly drops.
      Tasks.reconcile_occurrences(utc(~D[2026-06-28], ~T[21:05:00]))

      # You re-tap at 21:10, still inside 17:00-01:00. This must surface tonight's
      # already-done dinner (so the UI reads "already done") — not the breakfast
      # context and not tomorrow's fresh occurrence.
      second = utc(~D[2026-06-28], ~T[21:10:00])
      assert {:ok, occ} = Links.resolve_execute(scope, link.id, second)

      assert occ.task_id == dinner.id
      refute is_nil(occ.completed_at)
      assert DateTime.to_date(DateTime.shift_zone!(occ.due_at, "Etc/UTC")) == ~D[2026-06-28]
    end

    test "a missing occurrence fails loud and is not silently created" do
      scope = owner_scope_fixture()
      task = task_fixture(scope)
      link = link_fixture(scope)
      bind_fixture(scope, link, task)

      Repo.delete_all(from(o in TaskOccurrence, where: o.task_id == ^task.id))

      now = utc(~D[2026-06-28], ~T[09:00:00])

      log =
        capture_log(fn ->
          assert {:error, :no_occurrence} = Links.resolve_execute(scope, link.id, now)
        end)

      assert log =~ "no current occurrence"
      # The reconcile loop owns generation; execute must not paper over the gap.
      assert Repo.aggregate(from(o in TaskOccurrence, where: o.task_id == ^task.id), :count) == 0
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
