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
          <.button navigate={~p"/households/#{@household}/tasks"}>Back</.button>
        </:actions>
      </.header>

      <div id="task-status" class="mt-4">
        <span class={["badge", @done? && "badge-success"]} data-status={@status}>
          {@status}
        </span>
        <span :if={@completion} class="ml-2 opacity-70">
          by {@completion.user && (@completion.user.display_name || @completion.user.email)}
        </span>
      </div>

      <.header>Assigned tags</.header>
      <.table id="commands" rows={@commands}>
        <:col :let={command} label="Tag">{command.nfc_tag.label || command.nfc_tag.external_id}</:col>
        <:col :let={command} label="Command">{command.command_type}</:col>
      </.table>

      <section :if={@unassigned_tags != []} class="mt-8">
        <.header>Assign a tag</.header>
        <.form for={@assign_form} id="assign-form" phx-submit="assign">
          <.input
            field={@assign_form[:tag_id]}
            type="select"
            label="Tag"
            options={Enum.map(@unassigned_tags, &{&1.label || &1.external_id, &1.id})}
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
  def handle_event("assign", %{"tag_id" => tag_id}, socket) do
    case Automation.assign_tag(socket.assigns.current_scope, socket.assigns.task, tag_id) do
      {:ok, _command} ->
        {:noreply, socket |> put_flash(:info, "Tag assigned.") |> load(socket.assigns.task)}

      {:error, %Ecto.Changeset{}} ->
        {:noreply, put_flash(socket, :error, "Could not assign that tag.")}
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
    |> assign(:unassigned_tags, Automation.list_unassigned_tags(scope))
    |> assign(:assign_form, to_form(%{"tag_id" => nil}))
  end
end
