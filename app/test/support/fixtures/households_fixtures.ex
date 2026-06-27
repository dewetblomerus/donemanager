defmodule DoneManager.HouseholdsFixtures do
  @moduledoc "Test fixtures for the Households context."

  import DoneManager.AccountsFixtures

  alias DoneManager.Accounts.Scope
  alias DoneManager.Households

  @doc "Creates a household owned by the scope's user and returns the household."
  def household_fixture(%Scope{} = scope, attrs \\ %{}) do
    attrs = Enum.into(attrs, %{name: "Home", timezone: "Etc/UTC"})
    {:ok, household} = Households.create_household(scope, attrs)
    household
  end

  @doc "A scope whose user owns a freshly-created household."
  def owner_scope_fixture do
    scope = user_scope_fixture()
    household = household_fixture(scope)
    Scope.put_household(scope, household)
  end
end
