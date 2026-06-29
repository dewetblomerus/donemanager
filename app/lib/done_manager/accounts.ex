defmodule DoneManager.Accounts do
  @moduledoc "Users and Auth0 sign-in."

  import Ecto.Query, warn: false

  alias DoneManager.Accounts.User
  alias DoneManager.Repo

  def get_user(id), do: Repo.get(User, id)

  def get_user_by_auth0_sub(auth0_sub), do: Repo.get_by(User, auth0_sub: auth0_sub)

  @doc "Updates user-editable settings (display name, quiet hours, Pushover key)."
  def update_user_settings(%User{} = user, attrs) do
    user
    |> User.settings_changeset(attrs)
    |> Repo.update()
  end

  @doc "Changeset for the user settings form."
  def change_user_settings(%User{} = user, attrs \\ %{}) do
    User.settings_changeset(user, attrs)
  end

  @doc """
  Finds or creates the user for an Auth0 `Ueberauth.Auth` struct, keyed on the
  stable `auth0_sub`. Profile fields are refreshed on every sign-in.
  """
  def upsert_with_auth0(%Ueberauth.Auth{} = auth) do
    attrs = %{
      auth0_sub: auth.uid,
      email: auth.info.email,
      display_name: auth.info.name
    }

    case get_user_by_auth0_sub(auth.uid) do
      nil -> %User{} |> User.changeset(attrs) |> Repo.insert()
      user -> user |> User.changeset(attrs) |> Repo.update()
    end
  end
end
