defmodule DoneManagerWeb.LayoutsTest do
  use DoneManagerWeb.ConnCase, async: true

  import DoneManager.AccountsFixtures
  import DoneManager.HouseholdsFixtures
  import Phoenix.LiveViewTest

  test "app nav links to current household tasks and links when present", %{conn: conn} do
    scope = owner_scope_fixture()
    conn = log_in_user(conn, scope.user)

    {:ok, _view, html} = live(conn, ~p"/households")

    assert html =~ ~s(href="/households/#{scope.household.id}/tasks")
    assert html =~ ~s(href="/households/#{scope.household.id}/links")
    assert html =~ ~r/>\s*Tasks\s*<\/a>/
    assert html =~ ~r/>\s*Links\s*<\/a>/
    refute html =~ ~r/>\s*Households\s*<\/a>/
  end

  test "app nav hides household-scoped links when there is no current household", %{conn: conn} do
    user = user_fixture()
    conn = log_in_user(conn, user)

    {:ok, _view, html} = live(conn, ~p"/households")

    refute html =~ ~s(/tasks")
    refute html =~ ~s(/links")
    assert html =~ ~r/>\s*Households\s*<\/a>/
    assert html =~ ~r/>\s*Invitations\s*<\/a>/
  end

  test "app nav links to households when the user has multiple households", %{conn: conn} do
    scope = user_scope_fixture()
    household_fixture(scope)
    household_fixture(scope, %{name: "Cabin"})

    conn = log_in_user(conn, scope.user)

    {:ok, _view, html} = live(conn, ~p"/households")

    assert html =~ ~r/>\s*Households\s*<\/a>/
  end
end
