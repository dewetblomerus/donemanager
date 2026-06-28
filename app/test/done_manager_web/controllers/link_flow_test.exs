defmodule DoneManagerWeb.LinkFlowTest do
  use DoneManagerWeb.ConnCase, async: true

  import DoneManager.HouseholdsFixtures
  import DoneManager.LinksFixtures
  import DoneManager.TasksFixtures

  alias DoneManager.Tasks

  describe "tap → execute flow" do
    test "a bound link redirects to the occurrence execute, which completes it", %{conn: conn} do
      scope = owner_scope_fixture()
      # interval task: no expiration, tappable any wall-clock time the suite runs.
      task = task_fixture(scope, %{"task_type" => "interval", "cadence_interval_minutes" => 180})
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

    test "an unassigned link redirects home with a notice", %{conn: conn} do
      scope = owner_scope_fixture()
      link = link_fixture(scope)

      conn = log_in_user(conn, scope.user)
      conn = get(conn, ~p"/links/#{link.id}")

      assert redirected_to(conn) == ~p"/households"
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
