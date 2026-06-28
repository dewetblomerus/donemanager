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
      assert html_response(conn, 200) =~ task.name
      assert Tasks.done?(Tasks.current_occurrence(task))
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
