defmodule DoneManagerWeb.AuthController do
  use DoneManagerWeb, :controller

  plug Ueberauth

  alias DoneManager.Accounts
  alias DoneManagerWeb.UserAuth

  def request(conn, _params), do: conn

  def callback(%{assigns: %{ueberauth_failure: _failure}} = conn, _params) do
    conn
    |> put_flash(:error, "Failed to authenticate.")
    |> redirect(to: ~p"/")
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    case Accounts.upsert_with_auth0(auth) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Welcome, #{user.display_name || user.email}!")
        |> UserAuth.log_in_user(user)

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Could not sign you in.")
        |> redirect(to: ~p"/")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "You have been logged out.")
    |> UserAuth.log_out_user()
  end
end
