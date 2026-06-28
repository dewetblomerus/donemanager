defmodule DoneManagerWeb.TagLive.IndexTest do
  use DoneManagerWeb.ConnCase, async: true

  import DoneManager.HouseholdsFixtures
  import Phoenix.LiveViewTest

  test "shows tag registration instructions with a generated scan URL", %{conn: conn} do
    scope = owner_scope_fixture()
    conn = log_in_user(conn, scope.user)

    {:ok, _view, html} = live(conn, ~p"/households/#{scope.household}/tags")
    document = LazyHTML.from_fragment(html)

    assert LazyHTML.query(document, "#tag-registration-instructions") != []
    assert LazyHTML.query(document, "#copy-tag-registration-url") != []

    [url] =
      document
      |> LazyHTML.query("#tag-registration-url")
      |> LazyHTML.attribute("value")

    assert url =~
             ~r"/v1/tags/[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[0-9a-f]{4}-[0-9a-f]{12}/scans$"
  end
end
