defmodule DoneManagerWeb.PageControllerTest do
  use DoneManagerWeb.ConnCase

  import DoneManager.HouseholdsFixtures

  test "GET / shows a log in link when signed out", %{conn: conn} do
    conn = get(conn, ~p"/")
    response = html_response(conn, 200)
    assert response =~ "Done Manager"
    assert response =~ ~p"/auth/auth0"
  end

  test "GET / redirects signed-in users to their best home", %{conn: conn} do
    scope = owner_scope_fixture()

    conn =
      conn
      |> log_in_user(scope.user)
      |> get(~p"/")

    assert redirected_to(conn) == ~p"/households/#{scope.household}"
  end
end
