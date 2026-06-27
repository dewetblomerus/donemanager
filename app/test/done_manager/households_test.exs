defmodule DoneManager.HouseholdsTest do
  use DoneManager.DataCase, async: true

  import DoneManager.AccountsFixtures
  import DoneManager.HouseholdsFixtures

  alias DoneManager.Accounts.Scope
  alias DoneManager.Households

  describe "create_household/2" do
    test "creates the household and makes the user its owner" do
      scope = user_scope_fixture()

      assert {:ok, household} =
               Households.create_household(scope, %{name: "Home", timezone: "Etc/UTC"})

      assert household.name == "Home"

      scope = Scope.put_household(scope, household)
      assert [membership] = Households.list_memberships(scope)
      assert membership.user_id == scope.user.id
      assert membership.role == "owner"
      assert Households.owner?(scope)
    end

    test "rejects a timezone that is not in the offered list" do
      scope = user_scope_fixture()

      assert {:error, changeset} =
               Households.create_household(scope, %{name: "Home", timezone: "Mars/Olympus"})

      assert "is invalid" in errors_on(changeset).timezone
    end
  end

  describe "household isolation (default-deny)" do
    test "list_households only returns the user's own households" do
      owner = owner_scope_fixture()
      _other = owner_scope_fixture()

      assert [household] = Households.list_households(owner)
      assert household.id == owner.household.id
    end

    test "a fresh user with no membership sees nothing" do
      assert Households.list_households(user_scope_fixture()) == []
    end

    test "get_household! raises for a household the user does not belong to" do
      owner = owner_scope_fixture()
      stranger = user_scope_fixture()

      assert_raise Ecto.NoResultsError, fn ->
        Households.get_household!(stranger, owner.household.id)
      end
    end
  end

  describe "invite_by_email/2" do
    test "an owner can invite, a non-owner cannot" do
      owner = owner_scope_fixture()

      assert {:ok, invitation} =
               Households.invite_by_email(owner, %{"invitee_email" => "Friend@Example.com"})

      assert invitation.invitee_email == "friend@example.com"
      assert invitation.status == "pending"

      member = user_scope_fixture()
      member_in_household = Scope.put_household(member, owner.household)

      assert {:error, :unauthorized} =
               Households.invite_by_email(member_in_household, %{
                 "invitee_email" => "x@example.com"
               })
    end
  end

  describe "accept_invitation/2" do
    test "invitee signs up and the invite converts to a membership" do
      owner = owner_scope_fixture()
      invitee = user_fixture(email: "invitee@example.com")

      {:ok, invitation} =
        Households.invite_by_email(owner, %{"invitee_email" => "invitee@example.com"})

      assert {:ok, _} = Households.accept_invitation(invitee, invitation.id)

      invitee_scope = Scope.for_user(invitee)
      assert [household] = Households.list_households(invitee_scope)
      assert household.id == owner.household.id
      assert Households.list_pending_invitations_for_user(invitee) == []
    end

    test "cannot accept an invitation addressed to a different email" do
      owner = owner_scope_fixture()

      {:ok, invitation} =
        Households.invite_by_email(owner, %{"invitee_email" => "someone@example.com"})

      stranger = user_fixture(email: "stranger@example.com")
      assert {:error, :invalid_invitation} = Households.accept_invitation(stranger, invitation.id)
      assert Households.list_households(Scope.for_user(stranger)) == []
    end
  end
end
