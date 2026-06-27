defmodule DoneManagerWeb.TaskLive.Form do
  use DoneManagerWeb, :live_view

  alias DoneManager.Accounts.Scope
  alias DoneManager.Households
  alias DoneManager.Tasks
  alias DoneManager.Tasks.Task

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>New task in {@household.name}</.header>

      <.form for={@form} id="task-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:name]} type="text" label="Name" />
        <.input field={@form[:description]} type="text" label="Description" />
        <footer class="mt-4 flex gap-2">
          <.button variant="primary" phx-disable-with="Saving...">Save task</.button>
          <.button navigate={~p"/households/#{@household}/tasks"}>Cancel</.button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => household_id}, _session, socket) do
    household = Households.get_household!(socket.assigns.current_scope, household_id)
    scope = Scope.put_household(socket.assigns.current_scope, household)

    {:ok,
     socket
     |> assign(:current_scope, scope)
     |> assign(:household, household)
     |> assign(:form, to_form(Tasks.change_task()))}
  end

  @impl true
  def handle_event("validate", %{"task" => params}, socket) do
    changeset = Tasks.change_task(%Task{}, params)
    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"task" => params}, socket) do
    case Tasks.create_task(socket.assigns.current_scope, params) do
      {:ok, task} ->
        {:noreply,
         socket
         |> put_flash(:info, "Task created.")
         |> push_navigate(to: ~p"/tasks/#{task}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, action: :insert))}
    end
  end
end
