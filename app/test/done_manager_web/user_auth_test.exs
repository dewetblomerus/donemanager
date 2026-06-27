defmodule DoneManagerWeb.UserAuthTest do
  use DoneManagerWeb.ConnCase, async: true

  import DoneManager.AccountsFixtures
  import Phoenix.LiveViewTest

  describe "default-deny on protected routes" do
    test "redirects to the landing page when signed out", %{conn: conn} do
      conn = get(conn, ~p"/households")
      assert redirected_to(conn) == ~p"/"
    end

    test "a signed-in user reaches their (empty) households list", %{conn: conn} do
      conn = conn |> log_in_user(user_fixture()) |> get(~p"/households")
      assert html_response(conn, 200) =~ "Your households"
    end

    test "live default-deny redirects an unauthenticated socket", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/households")
    end
  end

  describe "invite to membership flow over LiveView" do
    test "invitee accepts and joins the household", %{conn: conn} do
      owner_scope = DoneManager.HouseholdsFixtures.owner_scope_fixture()

      {:ok, _invitation} =
        DoneManager.Households.invite_by_email(owner_scope, %{
          "invitee_email" => "joiner@example.com"
        })

      invitee = user_fixture(email: "joiner@example.com")
      conn = log_in_user(conn, invitee)

      {:ok, lv, _html} = live(conn, ~p"/invitations")

      assert lv |> element("button", "Accept") |> render_click()
      assert_redirect(lv, ~p"/households")

      assert [household] =
               DoneManager.Households.list_households(
                 DoneManager.Accounts.Scope.for_user(invitee)
               )

      assert household.id == owner_scope.household.id
    end
  end
end
