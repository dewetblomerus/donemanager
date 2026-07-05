defmodule DoneManagerWeb.LinkController do
  @moduledoc """
  The stable tag contract: `GET /links/:id`. Resolves the tapped link to the
  task occurrence that should be acted on and redirects to its execute action
  when executable. Outside execution hours, it redirects to the inert status URL
  so reloads cannot later execute the task. Carries no side effect itself. See
  architecture/database.md.
  """

  use DoneManagerWeb, :controller

  alias DoneManager.Links

  def execute(conn, %{"id" => id}) do
    case Links.resolve_execute(conn.assigns.current_scope, id) do
      {:ok, occurrence} ->
        redirect(conn, to: ~p"/occurrences/#{occurrence.id}/execute")

      {:warning, _context} ->
        redirect(conn, to: ~p"/links/#{id}/status")

      {:error, :not_found} ->
        claim_new_link(conn, id)

      {:error, :unassigned} ->
        conn
        |> put_flash(:info, "This link isn’t assigned to a task yet. Assign it in the app.")
        |> redirect(to: ~p"/households")

      {:error, :no_occurrence} ->
        no_occurrence(conn)
    end
  end

  def status(conn, %{"id" => id}) do
    case Links.resolve_status(conn.assigns.current_scope, id) do
      {:ok, context} ->
        conn
        |> put_view(html: DoneManagerWeb.OccurrenceHTML)
        |> render(:link_status, context: context)

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "That link isn’t available.")
        |> redirect(to: ~p"/households")

      {:error, :unassigned} ->
        conn
        |> put_flash(:info, "This link isn’t assigned to a task yet. Assign it in the app.")
        |> redirect(to: ~p"/households")

      {:error, :no_occurrence} ->
        no_occurrence(conn)
    end
  end

  # Anomaly: the reconcile loop should always keep an occurrence open, so this
  # path is logged loudly in Links. Keep the UI soft — the loop heals within a
  # minute, so invite a retry rather than surfacing an error.
  defp no_occurrence(conn) do
    conn
    |> put_flash(:info, "This task isn’t ready just yet. Give it a moment and tap again.")
    |> redirect(to: ~p"/households")
  end

  defp claim_new_link(conn, id) do
    case Links.claim_new_link_for_only_household(conn.assigns.current_scope, id) do
      {:ok, link} ->
        conn
        |> put_flash(:info, "Link added. Name it and assign it to a task.")
        |> redirect(to: ~p"/households/#{link.household_id}/links")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "That link isn’t available.")
        |> redirect(to: ~p"/households")
    end
  end
end
