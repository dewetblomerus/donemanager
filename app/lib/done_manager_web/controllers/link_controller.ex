defmodule DoneManagerWeb.LinkController do
  @moduledoc """
  The stable tag contract: `GET /links/:id`. Resolves the tapped link to the
  task occurrence that should be acted on and redirects to its execute action.
  Carries no side effect itself — it only routes. See architecture/database.md.
  """

  use DoneManagerWeb, :controller

  alias DoneManager.Links

  def execute(conn, %{"id" => id}) do
    case Links.resolve_execute(conn.assigns.current_scope, id) do
      {:ok, occurrence} ->
        redirect(conn, to: ~p"/occurrences/#{occurrence.id}/execute")

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "That link isn’t available.")
        |> redirect(to: ~p"/households")

      {:error, :unassigned} ->
        conn
        |> put_flash(:info, "This link isn’t assigned to a task yet. Assign it in the app.")
        |> redirect(to: ~p"/households")
    end
  end
end
