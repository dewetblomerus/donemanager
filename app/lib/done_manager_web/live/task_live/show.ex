defmodule DoneManagerWeb.TaskLive.Show do
  use DoneManagerWeb, :live_view

  alias DoneManager.Accounts.Scope
  alias DoneManager.Automation
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
        <span :if={@completion} class="opacity-70">
          Completed by {completed_by(@completion)} at {DoneManager.Timezones.format(
            @completion.occurred_at,
            @household.timezone
          )} (via {@completion.source})
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
        <:item :if={@task.cadence_frequency} title="Frequency">{@task.cadence_frequency}</:item>
        <:item :if={@task.cadence_weekdays != []} title="Weekdays">
          {Enum.join(@task.cadence_weekdays, ", ")}
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
        <:item title="NFC scan window">{task_scan_window(@task)}</:item>
        <:item title="Active">{@task.active}</:item>
      </.list>

      <.header>Assigned tags</.header>
      <.table id="commands" rows={@commands}>
        <:col :let={command} label="Tag">{command.nfc_tag.label || command.nfc_tag.external_id}</:col>
        <:col :let={_command} label="A scan will">{scan_action(@task)}</:col>
      </.table>

      <section :if={@commands == [] and @assignable_tags != []} class="mt-8">
        <.header>Assign a tag</.header>
        <.form for={@assign_form} id="assign-form" phx-submit="assign">
          <.input
            field={@assign_form[:tag_id]}
            type="select"
            label="Tag"
            options={Enum.map(@assignable_tags, &{&1.label || &1.external_id, &1.id})}
          />
          <footer class="mt-4">
            <.button variant="primary" phx-disable-with="Assigning...">Assign tag</.button>
          </footer>
        </.form>
      </section>
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
  def handle_event("assign", params, socket) do
    case Automation.assign_tag(
           socket.assigns.current_scope,
           socket.assigns.task,
           params["tag_id"],
           params
         ) do
      {:ok, _command} ->
        {:noreply, socket |> put_flash(:info, "Tag assigned.") |> load(socket.assigns.task)}

      {:error, %Ecto.Changeset{}} ->
        {:noreply, put_flash(socket, :error, "Could not assign that tag.")}
    end
  end

  def handle_event("complete", _params, socket) do
    case Tasks.complete_via_web(socket.assigns.current_scope, socket.assigns.task) do
      {:ok, :completed} ->
        {:noreply, socket |> put_flash(:info, "Marked complete.") |> load(socket.assigns.task)}

      {:ok, :duplicate_completion_attempted} ->
        {:noreply, socket |> put_flash(:info, "Already complete.") |> load(socket.assigns.task)}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You can't complete this task.")}
    end
  end

  defp load(socket, task) do
    scope = socket.assigns.current_scope
    occurrence = Tasks.current_occurrence(task)
    done? = occurrence != nil and Tasks.done?(occurrence)
    completion = occurrence && Tasks.completion_event(occurrence)

    socket
    |> assign(:done?, done?)
    |> assign(:status, if(done?, do: "done", else: "open"))
    |> assign(:completion, completion)
    |> assign(:commands, Automation.list_commands_for_task(task))
    |> assign(:assignable_tags, Automation.list_assignable_tags(scope))
    |> assign(:assign_form, to_form(%{"tag_id" => nil}))
  end

  defp completed_by(%{user: nil}), do: "a shared device"
  defp completed_by(%{user: user}), do: user.display_name || user.email

  defp scan_action(%{task_type: "timer"}), do: "toggle the timer"
  defp scan_action(_task), do: "complete the task"

  defp task_scan_window(%{scan_window_start_time: nil, scan_window_end_time: nil}), do: "All day"

  defp task_scan_window(task) do
    "#{format_time(task.scan_window_start_time)}-#{format_time(task.scan_window_end_time)}"
  end

  defp format_time(%Time{} = time), do: Calendar.strftime(time, "%H:%M")
end
