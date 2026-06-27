defmodule DoneManagerWeb.TaskLive.Index do
  use DoneManagerWeb, :live_view

  alias DoneManager.Tasks

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Tasks
        <:actions>
          <.button variant="primary" navigate={~p"/tasks/new"}>
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
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :tasks, load_tasks(socket.assigns.current_scope))}
  end

  defp load_tasks(scope) do
    Enum.map(Tasks.list_tasks(scope), fn task ->
      occurrence = Tasks.current_occurrence(task)
      status = if occurrence && Tasks.done?(occurrence), do: "done", else: "open"
      Map.put(task, :status, status)
    end)
  end
end
