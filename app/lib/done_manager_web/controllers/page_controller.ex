defmodule DoneManagerWeb.PageController do
  use DoneManagerWeb, :controller

  alias DoneManagerWeb.HomeRedirector

  def home(conn, _params) do
    if current_scope = conn.assigns[:current_scope] do
      redirect(conn, to: HomeRedirector.path(current_scope))
    else
      render(conn, :home)
    end
  end
end
