defmodule DoneManager.IntegrationsTest do
  use DoneManager.DataCase, async: true

  import DoneManager.AccountsFixtures
  import DoneManager.HouseholdsFixtures
  import DoneManager.IntegrationsFixtures

  alias DoneManager.Accounts.Scope
  alias DoneManager.Households
  alias DoneManager.Integrations

  describe "create_token/2" do
    test "an owner mints a token; a non-owner cannot" do
      owner = owner_scope_fixture()
      assert {:ok, token, plaintext} = Integrations.create_token(owner, %{label: "Phone"})
      assert token.household_id == owner.household.id
      assert token.user_id == owner.user.id
      assert token.created_by_user_id == owner.user.id
      assert String.starts_with?(plaintext, token.prefix <> ".")
      refute plaintext == token.token_hash

      member = Scope.put_household(user_scope_fixture(), owner.household)
      assert {:error, :unauthorized} = Integrations.create_token(member)
    end

    test "the owner can mint a token that belongs to another member" do
      owner = owner_scope_fixture()

      {:ok, invitation} =
        Households.invite_by_email(owner, %{"invitee_email" => "kid@example.com"})

      kid = user_fixture(email: "kid@example.com")
      {:ok, _} = Households.accept_invitation(kid, invitation.id)

      assert {:ok, token, _plaintext} = Integrations.create_token(owner, %{user_id: kid.id})
      # Acts as the member (attribution) but minted by the owner.
      assert token.user_id == kid.id
      assert token.created_by_user_id == owner.user.id
    end

    test "rejects a token for a user outside the household" do
      owner = owner_scope_fixture()
      stranger = user_fixture()
      assert {:error, :not_a_member} = Integrations.create_token(owner, %{user_id: stranger.id})
    end
  end

  describe "revoke_token/2" do
    test "an owner revokes; revoking is idempotent; a non-owner cannot" do
      owner = owner_scope_fixture()
      {token, plaintext} = token_fixture(owner)

      assert {:ok, revoked} = Integrations.revoke_token(owner, token.id)
      assert revoked.revoked_at
      assert :error = Integrations.authenticate(plaintext)

      first_revoked_at = revoked.revoked_at
      assert {:ok, again} = Integrations.revoke_token(owner, token.id)
      assert again.revoked_at == first_revoked_at

      member = Scope.put_household(user_scope_fixture(), owner.household)
      assert {:error, :unauthorized} = Integrations.revoke_token(member, token.id)
    end
  end

  describe "authenticate/1" do
    test "resolves a valid plaintext token to its household" do
      owner = owner_scope_fixture()
      {token, plaintext} = token_fixture(owner)

      assert {:ok, authed} = Integrations.authenticate(plaintext)
      assert authed.id == token.id
      assert authed.household.id == owner.household.id
    end

    test "rejects a garbage or revoked token" do
      owner = owner_scope_fixture()
      {token, plaintext} = token_fixture(owner)

      assert :error = Integrations.authenticate("nope.nope")
      assert :error = Integrations.authenticate(token.prefix <> ".wrongsecret")

      {:ok, _} = token |> Ecto.Changeset.change(revoked_at: DateTime.utc_now()) |> Repo.update()
      assert :error = Integrations.authenticate(plaintext)
    end
  end
end
