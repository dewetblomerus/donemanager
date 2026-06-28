defmodule DoneManagerWeb.UserAuth do
  @moduledoc """
  Session-based authentication built on the Auth0 sign-in.

  Loads the current user from the session, builds a `%Scope{}` with their
  current household, and enforces default-deny: no user means no access.
  """

  use DoneManagerWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias DoneManager.Accounts
  alias DoneManager.Accounts.Scope
  alias DoneManager.Households
  alias DoneManagerWeb.HomeRedirector
  alias Phoenix.LiveView

  @doc "Logs in a user by storing their id in a renewed session."
  def log_in_user(conn, user) do
    conn
    |> renew_session()
    |> put_session(:user_id, user.id)
    |> redirect(to: HomeRedirector.path_for_user(user))
  end

  @doc "Logs out the current user and clears the session."
  def log_out_user(conn) do
    conn
    |> renew_session()
    |> redirect(to: ~p"/")
  end

  defp renew_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  @doc "Plug: assigns `:current_scope` from the session (nil when logged out)."
  def fetch_current_scope(conn, _opts) do
    assign(conn, :current_scope, scope_from_session(get_session(conn, :user_id)))
  end

  @doc "Plug: requires an authenticated user, else redirects to the landing page."
  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_scope] do
      conn
    else
      conn
      |> put_flash(:error, "You must log in to access this page.")
      |> redirect(to: ~p"/")
      |> halt()
    end
  end

  @doc """
  LiveView `on_mount` callbacks:

    * `:mount_current_scope` - assigns `:current_scope`, may be nil.
    * `:require_authenticated` - halts to the landing page when logged out.
  """
  def on_mount(:mount_current_scope, _params, session, socket) do
    {:cont, assign_current_scope(socket, session)}
  end

  def on_mount(:require_authenticated, _params, session, socket) do
    socket = assign_current_scope(socket, session)

    if socket.assigns.current_scope do
      {:cont, socket}
    else
      socket =
        socket
        |> LiveView.put_flash(:error, "You must log in to access this page.")
        |> LiveView.redirect(to: ~p"/")

      {:halt, socket}
    end
  end

  defp assign_current_scope(socket, session) do
    Phoenix.Component.assign_new(socket, :current_scope, fn ->
      scope_from_session(session["user_id"])
    end)
  end

  defp scope_from_session(nil), do: nil

  defp scope_from_session(user_id) do
    case Accounts.get_user(user_id) do
      nil ->
        nil

      user ->
        scope = Scope.for_user(user)
        Scope.put_household(scope, Households.default_household(scope))
    end
  end
end
