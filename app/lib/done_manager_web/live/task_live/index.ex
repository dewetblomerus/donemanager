defmodule DoneManagerWeb.TaskLive.Index do
  use DoneManagerWeb, :live_view

  alias DoneManager.Accounts.Scope
  alias DoneManager.Households
  alias DoneManager.Tasks

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Tasks in {@household.name}
        <:subtitle>
          <.link navigate={~p"/households/#{@household}"} class="link">Back to household</.link>
        </:subtitle>
        <:actions>
          <.button variant="primary" navigate={~p"/households/#{@household}/tasks/new"}>
            <.icon name="hero-plus" /> New task
          </.button>
        </:actions>
      </.header>

      <.table
        id="tasks"
        rows={@tasks}
        row_click={fn task -> JS.navigate(~p"/tasks/#{task}") end}
      >
        <:col :let={task} label="Name">{task.name}</:col>
        <:col :let={task} label="Status">{task.status}</:col>
      </.table>

      <p :if={@tasks == []} class="mt-4 opacity-70">
        No tasks yet. Create one to get started.
      </p>
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
     |> assign(:tasks, load_tasks(scope))}
  end

  defp load_tasks(scope) do
    Enum.map(Tasks.list_tasks(scope), fn task ->
      occurrence = Tasks.current_occurrence(task)
      status = if occurrence && Tasks.done?(occurrence), do: "done", else: "open"
      Map.put(task, :status, status)
    end)
  end
end
