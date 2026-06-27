defmodule DoneManagerWeb.PageControllerTest do
  use DoneManagerWeb.ConnCase

  test "GET / shows a log in link when signed out", %{conn: conn} do
    conn = get(conn, ~p"/")
    response = html_response(conn, 200)
    assert response =~ "Done Manager"
    assert response =~ ~p"/auth/auth0"
  end
end
