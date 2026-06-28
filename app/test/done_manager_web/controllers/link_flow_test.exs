defmodule DoneManagerWeb.LinkFlowTest do
  use DoneManagerWeb.ConnCase, async: true

  import DoneManager.HouseholdsFixtures
  import DoneManager.LinksFixtures
  import DoneManager.TasksFixtures

  alias DoneManager.Tasks

  describe "tap → execute flow" do
    test "a bound link redirects to the occurrence execute, which completes it", %{conn: conn} do
      scope = owner_scope_fixture()
      task = task_fixture(scope)
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

    test "requires authentication", %{conn: conn} do
      scope = owner_scope_fixture()
      link = link_fixture(scope)

      conn = get(conn, ~p"/links/#{link.id}")
      assert redirected_to(conn) == ~p"/"
    end
  end
end
