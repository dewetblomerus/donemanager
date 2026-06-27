defmodule DoneManager.Accounts.Scope do
  @moduledoc """
  The request scope: the authenticated user and their current household.

  Every household-scoped data function takes a `%Scope{}` as its first argument,
  so cross-household access is structurally impossible rather than a per-query
  check. A signed-up user with no membership has `household: nil` and sees
  nothing — default-deny. See architecture/decisions.md.
  """

  alias DoneManager.Accounts.Scope
  alias DoneManager.Accounts.User
  alias DoneManager.Households.Household

  defstruct user: nil, household: nil

  @doc "Builds a scope for an authenticated user (no household yet)."
  def for_user(%User{} = user), do: %Scope{user: user}
  def for_user(nil), do: nil

  @doc "Sets the current household on the scope."
  def put_household(%Scope{} = scope, %Household{} = household),
    do: %{scope | household: household}

  def put_household(%Scope{} = scope, nil), do: %{scope | household: nil}
end
