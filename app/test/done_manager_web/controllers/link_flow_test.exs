defmodule DoneManagerWeb.LinkFlowTest do
  use DoneManagerWeb.ConnCase, async: true

  import DoneManager.HouseholdsFixtures
  import DoneManager.LinksFixtures
  import DoneManager.TasksFixtures

  alias DoneManager.Links.Link
  alias DoneManager.Repo
  alias DoneManager.Tasks

  describe "tap → execute flow" do
    test "a bound link redirects to the occurrence execute, which completes it", %{conn: conn} do
      scope = owner_scope_fixture()
      # interval task: no expiration, tappable any wall-clock time the suite runs.
      task = task_fixture(scope, %{"task_type" => "interval", "interval_minutes" => 180})
      link = link_fixture(scope)
      bind_fixture(scope, link, task)

      conn = log_in_user(conn, scope.user)

      conn = get(conn, ~p"/links/#{link.id}")
      execute_path = redirected_to(conn)
      assert execute_path =~ ~r"/occurrences/.+/execute"

      conn = get(recycle(conn) |> log_in_user(scope.user), execute_path)
      html = html_response(conn, 200)
      assert html =~ task.name
      assert html =~ "View task"
      assert html =~ "done"
      assert html =~ "bg-success"
      assert html =~ "Completed by Test User at"
      refute html =~ "Log out"
      assert Tasks.done?(Tasks.current_occurrence(task))
    end

    test "reloading the occurrence execute shows already done inside the done status", %{
      conn: conn
    } do
      scope = owner_scope_fixture()
      task = task_fixture(scope)
      occurrence = Tasks.current_occurrence(task)

      conn = log_in_user(conn, scope.user)

      conn = get(conn, ~p"/occurrences/#{occurrence.id}/execute")
      assert html_response(conn, 200) =~ "done"

      conn =
        get(recycle(conn) |> log_in_user(scope.user), ~p"/occurrences/#{occurrence.id}/execute")

      html = html_response(conn, 200)
      assert html =~ "Already done"
      assert html =~ "bg-red-900"
      assert html =~ "Completed by Test User at"
    end

    test "a bound timer link starts a countdown and shows the due time", %{conn: conn} do
      scope = owner_scope_fixture()

      task =
        task_fixture(scope, %{
          "name" => "Move Laundry To Dryer",
          "task_type" => "timer",
          "interval_minutes" => 60
        })

      link = link_fixture(scope)
      bind_fixture(scope, link, task)

      conn = log_in_user(conn, scope.user)
      conn = get(conn, ~p"/links/#{link.id}")
      execute_path = redirected_to(conn)

      conn = get(recycle(conn) |> log_in_user(scope.user), execute_path)
      html = html_response(conn, 200)

      assert html =~ "Move Laundry To Dryer"
      assert html =~ "Timer started"
      assert html =~ "Due at"
      assert html =~ "Mark done"
      assert html =~ "Cancel timer"
      refute html =~ "Completed by"

      occurrence = Tasks.current_occurrence(task)
      refute Tasks.done?(occurrence)
      assert DateTime.compare(occurrence.due_at, DateTime.utc_now()) == :gt
    end

    test "marking a running timer done makes the next scan start a new timer", %{conn: conn} do
      scope = owner_scope_fixture()

      task =
        task_fixture(scope, %{
          "name" => "Move Laundry To Dryer",
          "task_type" => "timer",
          "interval_minutes" => 60
        })

      link = link_fixture(scope)
      bind_fixture(scope, link, task)

      conn = log_in_user(conn, scope.user)
      conn = get(conn, ~p"/links/#{link.id}")
      first_execute_path = redirected_to(conn)

      conn = get(recycle(conn) |> log_in_user(scope.user), first_execute_path)
      first_occurrence = Tasks.current_occurrence(task)

      conn =
        post(
          recycle(conn) |> log_in_user(scope.user),
          ~p"/occurrences/#{first_occurrence.id}/complete"
        )

      html = html_response(conn, 200)
      assert html =~ "done"
      assert Tasks.done?(Tasks.current_occurrence(task))

      conn = get(recycle(conn) |> log_in_user(scope.user), ~p"/links/#{link.id}")
      second_execute_path = redirected_to(conn)
      refute second_execute_path == first_execute_path

      conn = get(recycle(conn) |> log_in_user(scope.user), second_execute_path)
      html = html_response(conn, 200)

      assert html =~ "Timer started"
      second_occurrence = Tasks.current_occurrence(task)
      assert second_occurrence.id != first_occurrence.id
      refute Tasks.done?(second_occurrence)
    end

    test "cancelling a running timer removes it", %{conn: conn} do
      scope = owner_scope_fixture()
      task = task_fixture(scope, %{"task_type" => "timer", "interval_minutes" => 60})
      occurrence = task |> Tasks.current_occurrence() |> Repo.preload(task: :household)
      {:started, occurrence} = Tasks.start_timer_occurrence(occurrence)

      conn = log_in_user(conn, scope.user)

      conn = delete(conn, ~p"/occurrences/#{occurrence.id}/timer")

      assert redirected_to(conn) == ~p"/tasks/#{task}"
      assert Tasks.current_occurrence(task) == nil
    end

    test "an unassigned link redirects home with a notice", %{conn: conn} do
      scope = owner_scope_fixture()
      link = link_fixture(scope)

      conn = log_in_user(conn, scope.user)
      conn = get(conn, ~p"/links/#{link.id}")

      assert redirected_to(conn) == ~p"/households"
    end

    test "a new valid UUIDv7 link is claimed for the user's only household", %{conn: conn} do
      scope = owner_scope_fixture()
      id = "019f1084-c889-7a9b-972f-037c1fcf88f7"

      conn = log_in_user(conn, scope.user)
      conn = get(conn, ~p"/links/#{id}")

      assert redirected_to(conn) == ~p"/households/#{scope.household.id}/links"

      link = Repo.get!(Link, id)
      assert link.household_id == scope.household.id
      assert link.label == nil
      assert link.active
    end

    test "an invalid new link id is not claimed", %{conn: conn} do
      scope = owner_scope_fixture()
      id = "not-a-uuidv7"
      link_count = Repo.aggregate(Link, :count)

      conn = log_in_user(conn, scope.user)
      conn = get(conn, ~p"/links/#{id}")

      assert redirected_to(conn) == ~p"/households"
      assert Repo.aggregate(Link, :count) == link_count
    end

    test "a link id already owned by another household is not claimed", %{conn: conn} do
      owner_scope = owner_scope_fixture()
      link = link_fixture(owner_scope)
      scanner_scope = owner_scope_fixture()

      conn = log_in_user(conn, scanner_scope.user)
      conn = get(conn, ~p"/links/#{link.id}")

      assert redirected_to(conn) == ~p"/households"
      assert Repo.get!(Link, link.id).household_id == owner_scope.household.id
    end

    test "a scan outside task execution hours redirects to inert status without completing",
         %{conn: conn} do
      scope = owner_scope_fixture()
      now = DateTime.utc_now()

      previous_task =
        task_fixture(scope, %{
          "name" => "Dog breakfast",
          "due_time" => time_attr(now, -90),
          "expiration_time" => time_attr(now, -60),
          "valid_from" => time_attr(now, -90)
        })

      next_task =
        task_fixture(scope, %{
          "name" => "Dog dinner",
          "due_time" => time_attr(now, 60),
          "expiration_time" => time_attr(now, 120),
          "valid_from" => time_attr(now, 60)
        })

      link = link_fixture(scope)
      bind_fixture(scope, link, previous_task)
      bind_fixture(scope, link, next_task)

      conn = log_in_user(conn, scope.user)
      conn = get(conn, ~p"/links/#{link.id}")

      assert redirected_to(conn) == ~p"/links/#{link.id}/status"

      conn = get(recycle(conn) |> log_in_user(scope.user), ~p"/links/#{link.id}/status")

      assert conn.request_path == ~p"/links/#{link.id}/status"
      html = html_response(conn, 200)
      assert html =~ "Outside task hours"
      assert html =~ "Previous occurrence"
      assert html =~ "Dog breakfast"
      assert html =~ "open"
      assert html =~ "Next occurrence"
      assert html =~ "Dog dinner"
      assert html =~ "Too early"
      assert html =~ "bg-warning"
      refute Tasks.done?(Tasks.current_occurrence(previous_task))
      refute Tasks.done?(Tasks.current_occurrence(next_task))
    end

    test "reloading link status during execution hours does not complete a task", %{conn: conn} do
      scope = owner_scope_fixture()
      now = DateTime.utc_now()

      task =
        task_fixture(scope, %{
          "name" => "Dog breakfast",
          "due_time" => time_attr(now, -5),
          "expiration_time" => time_attr(now, 5),
          "valid_from" => time_attr(now, -5)
        })

      link = link_fixture(scope)
      bind_fixture(scope, link, task)

      conn = log_in_user(conn, scope.user)
      conn = get(conn, ~p"/links/#{link.id}/status")

      html = html_response(conn, 200)
      assert html =~ "Link status"
      assert html =~ "Dog breakfast"
      refute Tasks.done?(Tasks.current_occurrence(task))
    end

    test "requires authentication", %{conn: conn} do
      scope = owner_scope_fixture()
      link = link_fixture(scope)

      conn = get(conn, ~p"/links/#{link.id}")
      assert redirected_to(conn) == ~p"/"
    end
  end

  defp time_attr(%DateTime{} = now, offset_minutes) do
    now
    |> DateTime.add(offset_minutes, :minute)
    |> DateTime.to_time()
    |> Time.truncate(:second)
    |> Time.to_string()
  end
end
