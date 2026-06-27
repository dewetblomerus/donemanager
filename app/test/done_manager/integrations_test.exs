defmodule DoneManager.IntegrationsTest do
  use DoneManager.DataCase, async: true

  import DoneManager.AccountsFixtures
  import DoneManager.HouseholdsFixtures
  import DoneManager.IntegrationsFixtures

  alias DoneManager.Accounts.Scope
  alias DoneManager.Integrations

  describe "create_token/2" do
    test "an owner mints a token; a non-owner cannot" do
      owner = owner_scope_fixture()
      assert {:ok, token, plaintext} = Integrations.create_token(owner, %{label: "Phone"})
      assert token.household_id == owner.household.id
      assert String.starts_with?(plaintext, token.prefix <> ".")
      refute plaintext == token.token_hash

      member = Scope.put_household(user_scope_fixture(), owner.household)
      assert {:error, :unauthorized} = Integrations.create_token(member)
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
