defmodule DoneManagerWeb.TaskLive.ShowTest do
  use DoneManagerWeb.ConnCase, async: true

  import DoneManager.HouseholdsFixtures
  import DoneManager.TasksFixtures
  import Phoenix.LiveViewTest

  alias DoneManager.Tasks

  test "shows the task and marks it complete from the web", %{conn: conn} do
    scope = owner_scope_fixture()
    task = task_fixture(scope)

    conn = log_in_user(conn, scope.user)
    {:ok, view, html} = live(conn, ~p"/tasks/#{task}")

    assert html =~ task.name
    assert has_element?(view, "[data-status=open]")

    view |> element("button", "Mark complete") |> render_click()

    assert has_element?(view, "[data-status=done]")
    assert Tasks.done?(Tasks.current_occurrence(task))
  end
end
