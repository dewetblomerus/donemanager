defmodule DoneManager.AccountsFixtures do
  @moduledoc "Test fixtures for the Accounts context."

  alias DoneManager.Accounts.Scope
  alias DoneManager.Accounts.User
  alias DoneManager.Repo

  def unique_email, do: "user#{System.unique_integer([:positive])}@example.com"

  def user_fixture(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        auth0_sub: "auth0|#{System.unique_integer([:positive])}",
        email: unique_email(),
        display_name: "Test User"
      })

    {:ok, user} = %User{} |> User.changeset(attrs) |> Repo.insert()
    user
  end

  @doc "A scope for a fresh user with no household (default-deny baseline)."
  def user_scope_fixture(user \\ user_fixture()), do: Scope.for_user(user)
end
