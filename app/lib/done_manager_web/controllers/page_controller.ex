defmodule DoneManagerWeb.PageController do
  use DoneManagerWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
