defmodule DoneManagerWeb.OccurrenceController do
  @moduledoc """
  The occurrence action and its inert show page.

  `GET /occurrences/:id/execute` performs the task-type action and renders the
  page. Scheduled/interval occurrences are completed; timer occurrences start
  their countdown due time.
  `GET /occurrences/:id` is the inert show. Both authorize the user by household
  membership via `Tasks.get_occurrence!/2`. See architecture/database.md.
  """

  use DoneManagerWeb, :controller

  alias DoneManager.Tasks

  def execute(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    occurrence = Tasks.get_occurrence!(scope, id)
    {outcome, occurrence} = execute_occurrence(occurrence, scope.user.id)

    conn
    |> render(:show, occurrence: occurrence, outcome: outcome)
  end

  def show(conn, %{"id" => id}) do
    occurrence = Tasks.get_occurrence!(conn.assigns.current_scope, id)
    render(conn, :show, occurrence: occurrence, outcome: nil)
  end

  def complete(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    occurrence = Tasks.get_occurrence!(scope, id)
    {outcome, occurrence} = Tasks.complete_occurrence(occurrence, scope.user.id)

    render(conn, :show, occurrence: occurrence, outcome: outcome)
  end

  def cancel_timer(conn, %{"id" => id}) do
    occurrence = Tasks.get_occurrence!(conn.assigns.current_scope, id)
    {:ok, _occurrence} = Tasks.cancel_timer_occurrence(occurrence)

    conn
    |> put_flash(:info, "Timer cancelled.")
    |> redirect(to: ~p"/tasks/#{occurrence.task}")
  end

  defp execute_occurrence(%{task: %{task_type: "timer"}} = occurrence, _user_id),
    do: Tasks.start_timer_occurrence(occurrence)

  defp execute_occurrence(occurrence, user_id) do
    Tasks.complete_occurrence(occurrence, user_id)
  end
end
