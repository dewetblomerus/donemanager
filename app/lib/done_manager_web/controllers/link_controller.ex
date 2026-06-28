defmodule DoneManagerWeb.LinkController do
  @moduledoc """
  The stable tag contract: `GET /links/:id`. Resolves the tapped link to the
  task occurrence that should be acted on and redirects to its execute action
  when executable. Outside execution hours, it stays on the link URL and renders
  read-only previous/next context. Carries no side effect itself. See
  architecture/database.md.
  """

  use DoneManagerWeb, :controller

  alias DoneManager.Links

  def execute(conn, %{"id" => id}) do
    case Links.resolve_execute(conn.assigns.current_scope, id) do
      {:ok, occurrence} ->
        redirect(conn, to: ~p"/occurrences/#{occurrence.id}/execute")

      {:warning, context} ->
        conn
        |> put_view(html: DoneManagerWeb.OccurrenceHTML)
        |> render(:scan_warning, context: context)

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
