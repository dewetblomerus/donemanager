defmodule DoneManagerWeb.LinkLive.IndexTest do
  use DoneManagerWeb.ConnCase, async: true

  import DoneManager.HouseholdsFixtures
  import DoneManager.LinksFixtures
  import DoneManager.TasksFixtures
  import Phoenix.LiveViewTest

  alias DoneManager.Links

  test "shows each link URL with a copy action", %{conn: conn} do
    scope = owner_scope_fixture()
    link = link_fixture(scope, %{"label" => "Washer"})
    tag_url = DoneManagerWeb.Endpoint.url() <> ~p"/links/#{link.id}"

    conn = log_in_user(conn, scope.user)
    {:ok, view, html} = live(conn, ~p"/households/#{scope.household}/links")

    assert html =~ "Washer"
    assert html =~ tag_url
    assert has_element?(view, ~s|button[aria-label="Copy tag URL for Washer"]|, "Copy")

    assert view
           |> element(~s|button[aria-label="Copy tag URL for Washer"]|)
           |> render_click() =~ "Link copied."
  end

  test "binds a timer task to a link", %{conn: conn} do
    scope = owner_scope_fixture()
    link = link_fixture(scope, %{"label" => "Laundry tag"})

    timer =
      task_fixture(scope, %{
        "name" => "Move laundry",
        "task_type" => "timer",
        "interval_minutes" => 60
      })

    conn = log_in_user(conn, scope.user)
    {:ok, view, _html} = live(conn, ~p"/households/#{scope.household}/links")

    assert view
           |> form("#bind-form-#{link.id}", task_id: timer.id)
           |> render_submit() =~ "Task bound."

    assert [timer.id] == Links.list_tasks_for_link(link) |> Enum.map(& &1.id)
    assert has_element?(view, "#link-#{link.id}", "Move laundry")
  end
end
