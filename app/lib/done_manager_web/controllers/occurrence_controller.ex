defmodule DoneManagerWeb.OccurrenceController do
  @moduledoc """
  The occurrence action and its inert show page.

  `GET /occurrences/:id/execute` marks the occurrence done (idempotent — the id
  pins one occurrence, so a reload just re-renders "done") and renders the page.
  `GET /occurrences/:id` is the inert show. Both authorize the user by household
  membership via `Tasks.get_occurrence!/2`. See architecture/database.md.
  """

  use DoneManagerWeb, :controller

  alias DoneManager.Tasks

  def execute(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    occurrence = Tasks.get_occurrence!(scope, id)
    {outcome, _occurrence} = Tasks.complete_occurrence(occurrence, scope.user.id)

    conn
    |> render(:show, occurrence: Tasks.get_occurrence!(scope, id), outcome: outcome)
  end

  def show(conn, %{"id" => id}) do
    occurrence = Tasks.get_occurrence!(conn.assigns.current_scope, id)
    render(conn, :show, occurrence: occurrence, outcome: nil)
  end
end
