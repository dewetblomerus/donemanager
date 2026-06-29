defmodule DoneManagerWeb.TaskLive.Index do
  use DoneManagerWeb, :live_view

  alias DoneManager.Accounts.Scope
  alias DoneManager.Households
  alias DoneManager.Tasks
  alias DoneManager.Tasks.TaskStatus

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
        rows={@rows}
        row_click={fn row -> JS.navigate(~p"/tasks/#{row.task}") end}
      >
        <:col :let={row} label="Name">{row.task.name}</:col>
        <:col :let={row} label="Type">{row.task.task_type}</:col>
        <:col :let={row} label="Status">
          <span
            class={["badge", TaskStatus.badge_class(row.status.state)]}
            data-status={row.status.state}
          >
            {TaskStatus.label(row.status.state)}
          </span>
        </:col>
      </.table>

      <p :if={@rows == []} class="mt-4 opacity-70">
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
     |> assign(:rows, load_rows(scope))}
  end

  defp load_rows(scope) do
    Enum.map(Tasks.list_tasks(scope), fn task ->
      %{task: task, status: Tasks.task_status(task)}
    end)
  end
end
