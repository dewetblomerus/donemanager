defmodule DoneManagerWeb.TaskLive.Form do
  use DoneManagerWeb, :live_view

  alias DoneManager.Accounts.Scope
  alias DoneManager.Households
  alias DoneManager.Tasks
  alias DoneManager.Tasks.Task

  @type_options [
    {"Scheduled — fixed times (e.g. feed the dog every morning)", "scheduled"},
    {"Every-so-often — due if not done in a while (e.g. let the dog out)", "interval"},
    {"Timer — on-demand countdown started by a tap (e.g. move the laundry)", "timer"}
  ]
  @frequency_options [{"Daily", "daily"}, {"Weekly", "weekly"}]
  @weekday_options [
    {"Monday", "mo"},
    {"Tuesday", "tu"},
    {"Wednesday", "we"},
    {"Thursday", "th"},
    {"Friday", "fr"},
    {"Saturday", "sa"},
    {"Sunday", "su"}
  ]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>{@page_title}</.header>

      <.form for={@form} id="task-form" phx-change="validate" phx-submit="save">
        <.input
          field={@form[:task_type]}
          type="select"
          label="Task type"
          prompt="Choose a type…"
          options={@type_options}
        />
        <.input field={@form[:name]} type="text" label="Name" />
        <.input field={@form[:description]} type="text" label="Description" />

        <%= case @task_type do %>
          <% "scheduled" -> %>
            <.input
              field={@form[:cadence_frequency]}
              type="select"
              label="Frequency"
              prompt="Choose…"
              options={@frequency_options}
            />
            <.input
              :if={@frequency == "weekly"}
              field={@form[:cadence_weekdays]}
              type="select"
              label="Weekdays"
              multiple
              options={@weekday_options}
            />
            <.input field={@form[:due_time]} type="time" label="Due time" />
            <.input field={@form[:expiration_time]} type="time" label="Expiration time (optional)" />
          <% "interval" -> %>
            <.input
              field={@form[:cadence_interval_minutes]}
              type="number"
              label="Interval in minutes (e.g. 180 for every 3 hours)"
              min="1"
            />
          <% "timer" -> %>
            <.input
              field={@form[:timer_minutes]}
              type="number"
              label="Timer minutes (how long the countdown runs after a tap)"
              min="1"
            />
          <% _ -> %>
        <% end %>

        <.input
          field={@form[:reminder_interval_minutes]}
          type="number"
          label="Reminder interval in minutes (optional; blank = single reminder)"
          min="1"
        />
        <div class="grid gap-4 sm:grid-cols-2">
          <.input
            field={@form[:execute_window_start_time]}
            type="time"
            label="Execute window starts (optional)"
          />
          <.input
            field={@form[:execute_window_end_time]}
            type="time"
            label="Execute window ends (optional)"
          />
        </div>
        <.input field={@form[:active]} type="checkbox" label="Active" />

        <footer class="mt-4 flex gap-2">
          <.button variant="primary" phx-disable-with="Saving...">Save task</.button>
          <.button navigate={@cancel_path}>Cancel</.button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    socket =
      socket
      |> assign(:type_options, @type_options)
      |> assign(:frequency_options, @frequency_options)
      |> assign(:weekday_options, @weekday_options)

    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  # New: the URL carries the household; start from a blank task.
  defp apply_action(socket, :new, %{"id" => household_id}) do
    household = Households.get_household!(socket.assigns.current_scope, household_id)
    scope = Scope.put_household(socket.assigns.current_scope, household)

    socket
    |> assign(:current_scope, scope)
    |> assign(:household, household)
    |> assign(:task, %Task{})
    |> assign(:page_title, "New task in #{household.name}")
    |> assign(:cancel_path, ~p"/households/#{household}/tasks")
    |> assign(:task_type, nil)
    |> assign(:frequency, nil)
    |> assign(:form, to_form(Tasks.change_task()))
  end

  # Edit: the URL carries the task id; resolve its household from it.
  defp apply_action(socket, :edit, %{"id" => task_id}) do
    task = Tasks.get_task!(socket.assigns.current_scope, task_id)
    household = Households.get_household!(socket.assigns.current_scope, task.household_id)
    scope = Scope.put_household(socket.assigns.current_scope, household)

    socket
    |> assign(:current_scope, scope)
    |> assign(:household, household)
    |> assign(:task, task)
    |> assign(:page_title, "Edit #{task.name}")
    |> assign(:cancel_path, ~p"/tasks/#{task}")
    |> assign(:task_type, task.task_type)
    |> assign(:frequency, task.cadence_frequency)
    |> assign(:form, to_form(Tasks.change_task(task)))
  end

  @impl true
  def handle_event("validate", %{"task" => params}, socket) do
    changeset = Tasks.change_task(socket.assigns.task, params)

    {:noreply,
     socket
     |> assign(:task_type, params["task_type"])
     |> assign(:frequency, params["cadence_frequency"])
     |> assign(:form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"task" => params}, socket) do
    save_task(socket, socket.assigns.live_action, params)
  end

  defp save_task(socket, :new, params) do
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

  defp save_task(socket, :edit, params) do
    case Tasks.update_task(socket.assigns.current_scope, socket.assigns.task, params) do
      {:ok, task} ->
        {:noreply,
         socket
         |> put_flash(:info, "Task updated.")
         |> push_navigate(to: ~p"/tasks/#{task}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, action: :update))}
    end
  end
end
