defmodule DoneManagerWeb.TaskLive.ShowTest do
  use DoneManagerWeb.ConnCase, async: true

  import DoneManager.HouseholdsFixtures
  import DoneManager.TasksFixtures
  import Phoenix.LiveViewTest

  alias DoneManager.Tasks

  test "shows the task and marks it complete from the web", %{conn: conn} do
    scope = owner_scope_fixture()
    # A window around "now" (household tz Etc/UTC) so the status is reliably open.
    from = Time.utc_now() |> Time.add(-3600) |> Time.truncate(:second)
    until = Time.utc_now() |> Time.add(3600) |> Time.truncate(:second)

    task =
      task_fixture(scope, %{
        "valid_from" => Time.to_string(from),
        "due_time" => Time.to_string(from),
        "expiration_time" => Time.to_string(until)
      })

    conn = log_in_user(conn, scope.user)
    {:ok, view, html} = live(conn, ~p"/tasks/#{task}")

    assert html =~ task.name
    assert has_element?(view, "[data-status=open]")

    view |> element("button", "Mark complete") |> render_click()

    assert has_element?(view, "[data-status=done]")
    assert Tasks.done?(Tasks.current_occurrence(task))
  end
end
