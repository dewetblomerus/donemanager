defmodule DoneManager.AccountsTest do
  use DoneManager.DataCase, async: true

  import DoneManager.AccountsFixtures

  alias DoneManager.Accounts
  alias DoneManager.Repo

  describe "update_user_settings/2" do
    test "persists the pushover key and decrypts it on reload" do
      user = user_fixture()

      assert {:ok, updated} =
               Accounts.update_user_settings(user, %{pushover_user_key: "u-abc123"})

      assert updated.pushover_user_key == "u-abc123"
      assert Accounts.get_user(user.id).pushover_user_key == "u-abc123"
    end

    test "stores the key encrypted, not as plaintext, in the database" do
      user = user_fixture()
      {:ok, _} = Accounts.update_user_settings(user, %{pushover_user_key: "u-abc123"})

      %{rows: [[raw]]} =
        Repo.query!("SELECT pushover_user_key FROM users WHERE id = $1", [
          Ecto.UUID.dump!(user.id)
        ])

      assert is_binary(raw)
      refute raw =~ "u-abc123"
    end

    test "updates the editable profile fields" do
      user = user_fixture()

      assert {:ok, updated} = Accounts.update_user_settings(user, %{display_name: "Renamed"})
      assert updated.display_name == "Renamed"
    end
  end
end
