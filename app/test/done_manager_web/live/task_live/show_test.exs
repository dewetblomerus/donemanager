defmodule DoneManagerWeb.TaskLive.ShowTest do
  use DoneManagerWeb.ConnCase, async: true

  import DoneManager.AutomationFixtures
  import DoneManager.HouseholdsFixtures
  import DoneManager.TasksFixtures
  import Phoenix.LiveViewTest

  alias DoneManager.Automation

  test "a tag assigned to one task can be assigned to another task", %{
    conn: conn
  } do
    scope = owner_scope_fixture()

    breakfast =
      task_fixture(scope, %{
        "name" => "Dog breakfast",
        "due_time" => "08:00:00",
        "scan_window_start_time" => "05:00",
        "scan_window_end_time" => "23:00"
      })

    dinner =
      task_fixture(scope, %{
        "name" => "Dog dinner",
        "due_time" => "18:00:00",
        "scan_window_start_time" => "05:00",
        "scan_window_end_time" => "23:00"
      })

    tag = tag_fixture(scope, label: "Dog food")
    command_fixture(scope, breakfast, tag)

    conn = log_in_user(conn, scope.user)
    {:ok, view, html} = live(conn, ~p"/tasks/#{dinner}")

    assert html =~ "Dog food"

    view
    |> element("#assign-form")
    |> render_submit(%{"tag_id" => tag.id})

    commands = Automation.list_commands_for_task(dinner)
    assert [command] = commands
    assert command.nfc_tag_id == tag.id
  end

  test "the task page does not offer another tag assignment after one is active", %{conn: conn} do
    scope = owner_scope_fixture()
    task = task_fixture(scope)
    tag = tag_fixture(scope)
    command_fixture(scope, task, tag)

    conn = log_in_user(conn, scope.user)
    {:ok, _view, html} = live(conn, ~p"/tasks/#{task}")

    refute html =~ ~s(id="assign-form")
  end
end
