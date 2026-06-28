defmodule DoneManagerWeb.TaskLive.Show do
  use DoneManagerWeb, :live_view

  alias DoneManager.Accounts.Scope
  alias DoneManager.Households
  alias DoneManager.Tasks

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@task.name}
        <:subtitle>{@task.description}</:subtitle>
        <:actions>
          <.button variant="primary" navigate={~p"/tasks/#{@task}/edit"}>Edit</.button>
          <.button navigate={~p"/households/#{@household}/tasks"}>Back</.button>
        </:actions>
      </.header>

      <div id="task-status" class="mt-4 flex items-center gap-3">
        <span class={["badge", @done? && "badge-success"]} data-status={@status}>
          {@status}
        </span>
        <span :if={@occurrence && @occurrence.completed_at} class="opacity-70">
          Completed by {completed_by(@occurrence)} at {DoneManager.Timezones.format(
            @occurrence.completed_at,
            @household.timezone
          )}
        </span>
        <.button
          :if={!@done?}
          variant="primary"
          phx-click="complete"
          phx-disable-with="Completing..."
        >
          Mark complete
        </.button>
      </div>

      <.list>
        <:item title="Type">{@task.task_type}</:item>
        <:item :if={@task.task_type == "scheduled"} title="Weekdays">
          {scheduled_weekdays(@task.cadence_weekdays)}
        </:item>
        <:item :if={@task.cadence_interval_minutes} title="Every">
          {@task.cadence_interval_minutes} min
        </:item>
        <:item :if={@task.due_time} title="Due time">{@task.due_time}</:item>
        <:item :if={@task.expiration_time} title="Expires">{@task.expiration_time}</:item>
        <:item :if={@task.timer_minutes} title="Timer">{@task.timer_minutes} min</:item>
        <:item :if={@task.reminder_interval_minutes} title="Reminder every">
          {@task.reminder_interval_minutes} min
        </:item>
        <:item title="Execute window">{execute_window(@task)}</:item>
        <:item title="Active">{@task.active}</:item>
      </.list>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    task = Tasks.get_task!(socket.assigns.current_scope, id)
    household = Households.get_household!(socket.assigns.current_scope, task.household_id)
    scope = Scope.put_household(socket.assigns.current_scope, household)

    {:ok,
     socket
     |> assign(:current_scope, scope)
     |> assign(:task, task)
     |> assign(:household, household)
     |> load(task)}
  end

  @impl true
  def handle_event("complete", _params, socket) do
    case Tasks.complete_via_web(socket.assigns.current_scope, socket.assigns.task) do
      {:ok, :completed} ->
        {:noreply, socket |> put_flash(:info, "Marked complete.") |> load(socket.assigns.task)}

      {:ok, :duplicate} ->
        {:noreply, socket |> put_flash(:info, "Already complete.") |> load(socket.assigns.task)}
    end
  end

  defp load(socket, task) do
    occurrence = Tasks.current_occurrence(task)
    done? = occurrence != nil and Tasks.done?(occurrence)

    socket
    |> assign(:occurrence, occurrence)
    |> assign(:done?, done?)
    |> assign(:status, if(done?, do: "done", else: "open"))
  end

  defp completed_by(%{completed_by: nil}), do: "a household member"
  defp completed_by(%{completed_by: user}), do: user.display_name || user.email

  defp execute_window(%{valid_from: nil, expiration_time: nil}), do: "All day"

  defp execute_window(task) do
    from = if task.valid_from, do: format_time(task.valid_from), else: "00:00"
    until = if task.expiration_time, do: format_time(task.expiration_time), else: "…"
    "#{from}-#{until}"
  end

  defp format_time(%Time{} = time), do: Calendar.strftime(time, "%H:%M")

  defp scheduled_weekdays([]), do: "Every day"
  defp scheduled_weekdays(days), do: Enum.join(days, ", ")
end
