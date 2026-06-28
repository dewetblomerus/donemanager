defmodule DoneManagerWeb.HomeRedirectorTest do
  use DoneManagerWeb.ConnCase, async: true

  import DoneManager.AccountsFixtures
  import DoneManager.HouseholdsFixtures

  alias DoneManager.Accounts.Scope
  alias DoneManager.Households
  alias DoneManagerWeb.HomeRedirector

  test "sends signed-out users to the public home page" do
    assert HomeRedirector.path(nil) == ~p"/"
  end

  test "sends users with no households and no invitations to the households index" do
    user = user_fixture()

    assert HomeRedirector.path_for_user(user) == ~p"/households"
  end

  test "sends users with pending invitations and no households to invitations" do
    owner_scope = owner_scope_fixture()
    invitee = user_fixture(email: "invitee@example.com")

    {:ok, _invitation} =
      Households.invite_by_email(owner_scope, %{"invitee_email" => invitee.email})

    assert HomeRedirector.path_for_user(invitee) == ~p"/invitations"
  end

  test "sends users with one household to that household" do
    scope = user_scope_fixture()
    household = household_fixture(scope)

    assert HomeRedirector.path(scope) == ~p"/households/#{household}"
  end

  test "sends users with multiple households to the households index" do
    scope = user_scope_fixture()
    household_fixture(scope)
    household_fixture(scope, %{name: "Cabin"})

    assert HomeRedirector.path(scope) == ~p"/households"
  end

  test "does not need the current household already attached to the scope" do
    scope = user_scope_fixture()
    household = household_fixture(scope)
    scope_without_household = Scope.put_household(scope, nil)

    assert HomeRedirector.path(scope_without_household) == ~p"/households/#{household}"
  end
end
