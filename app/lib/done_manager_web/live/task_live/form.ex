defmodule DoneManagerWeb.TaskLive.Form do
  use DoneManagerWeb, :live_view

  alias DoneManager.Accounts.Scope
  alias DoneManager.Households
  alias DoneManager.Tasks
  alias DoneManager.Tasks.Task

  @type_options [
    {"Scheduled — fixed times (e.g. feed the dog every morning)", "scheduled"},
    {"Every-so-often — due if not done in a while (e.g. let the dog out)", "interval"},
    {"On-demand timer — starts on a tap (e.g. move the laundry)", "one_off"}
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
      <.header>New task in {@household.name}</.header>

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
          <% "one_off" -> %>
            <p class="opacity-70">
              On-demand timers have no schedule. The delay is set on the tag's command when you assign it.
            </p>
          <% _ -> %>
        <% end %>

        <.input
          field={@form[:reminder_interval_minutes]}
          type="number"
          label="Reminder interval in minutes (optional; blank = single reminder)"
          min="1"
        />
        <.input field={@form[:active]} type="checkbox" label="Active" />

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
     |> assign(:type_options, @type_options)
     |> assign(:frequency_options, @frequency_options)
     |> assign(:weekday_options, @weekday_options)
     |> assign(:task_type, nil)
     |> assign(:frequency, nil)
     |> assign(:form, to_form(Tasks.change_task()))}
  end

  @impl true
  def handle_event("validate", %{"task" => params}, socket) do
    changeset = Tasks.change_task(%Task{}, params)

    {:noreply,
     socket
     |> assign(:task_type, params["task_type"])
     |> assign(:frequency, params["cadence_frequency"])
     |> assign(:form, to_form(changeset, action: :validate))}
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
