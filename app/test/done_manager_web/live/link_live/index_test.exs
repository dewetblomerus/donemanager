defmodule DoneManagerWeb.LinkLive.IndexTest do
  use DoneManagerWeb.ConnCase, async: true

  import DoneManager.HouseholdsFixtures
  import DoneManager.LinksFixtures
  import Phoenix.LiveViewTest

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
end
