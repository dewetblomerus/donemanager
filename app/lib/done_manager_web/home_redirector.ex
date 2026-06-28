defmodule DoneManagerWeb.HomeRedirector do
  @moduledoc """
  Chooses the best signed-in landing page for the current user.

  Keep canonical page behavior in the page modules themselves; this module only
  answers "where should home/logo/login send this user next?"
  """

  use DoneManagerWeb, :verified_routes

  alias DoneManager.Accounts.Scope
  alias DoneManager.Accounts.User
  alias DoneManager.Households

  def path(nil), do: ~p"/"

  def path(%Scope{user: %User{} = user} = scope) do
    case Households.list_households(scope) do
      [household] ->
        ~p"/households/#{household}"

      [_household | _households] ->
        ~p"/households"

      [] ->
        if Households.list_pending_invitations_for_user(user) == [] do
          ~p"/households"
        else
          ~p"/invitations"
        end
    end
  end

  def path_for_user(%User{} = user), do: user |> Scope.for_user() |> path()
end
