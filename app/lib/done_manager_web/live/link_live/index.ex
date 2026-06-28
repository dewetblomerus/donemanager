defmodule DoneManagerWeb.LinkLive.Index do
  use DoneManagerWeb, :live_view

  alias DoneManager.Accounts.Scope
  alias DoneManager.Households
  alias DoneManager.Links
  alias DoneManager.Tasks

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Links in {@household.name}
        <:subtitle>
          Create a link, write its URL onto an NFC tag or QR code, and bind it to one or more tasks.
        </:subtitle>
        <:actions>
          <.button variant="primary" phx-click="create">New link</.button>
          <.button navigate={~p"/households/#{@household}"}>Back</.button>
        </:actions>
      </.header>

      <div id="links" class="space-y-3">
        <div
          :for={link <- @links}
          id={"link-#{link.id}"}
          class="rounded-lg border border-base-300 p-4"
        >
          <div class="flex items-start justify-between gap-4">
            <p class="font-semibold">{link.label || "Unnamed link"}</p>
            <.link
              phx-click="delete"
              phx-value-id={link.id}
              data-confirm="Delete this link? Any tag carrying its URL will stop working."
              class="link text-error"
            >
              Delete
            </.link>
          </div>

          <div class="mt-2 rounded-lg border border-base-300 bg-base-100 p-3">
            <div class="flex items-center justify-between gap-3">
              <label
                for={"link-url-#{link.id}"}
                class="text-xs font-semibold uppercase tracking-wide text-base-content/60"
              >
                Tag URL
              </label>
              <button
                type="button"
                phx-click={
                  JS.dispatch("dm:copy-to-clipboard", detail: %{text: link_url(link)})
                  |> JS.push("copied")
                }
                class="btn btn-primary btn-soft btn-xs"
                aria-label={"Copy tag URL for #{link.label || "unnamed link"}"}
              >
                <.icon name="hero-clipboard-document" class="size-4" /> Copy
              </button>
            </div>
            <input
              id={"link-url-#{link.id}"}
              type="url"
              value={link_url(link)}
              readonly
              class="mt-2 w-full bg-transparent text-sm outline-none"
            />
          </div>

          <p class="mt-2 text-sm opacity-70">
            <%= case bound_tasks(link) do %>
              <% [] -> %>
                Not bound to any task yet.
              <% tasks -> %>
                Drives:
                <span class="inline-flex flex-wrap gap-x-2">
                  <span :for={task <- tasks}>
                    <.link navigate={~p"/tasks/#{task}"} class="link">{task.name}</.link>
                    <.link
                      phx-click="unbind"
                      phx-value-id={binding_id(link, task)}
                      class="link text-error"
                    >
                      ✕
                    </.link>
                  </span>
                </span>
            <% end %>
          </p>

          <.form
            for={form_for(@forms, link)}
            id={"link-form-#{link.id}"}
            phx-submit="rename"
            phx-value-id={link.id}
            class="mt-2 flex items-end gap-2"
          >
            <.input field={form_for(@forms, link)[:label]} type="text" placeholder="Name this link" />
            <.button variant="primary" phx-disable-with="Saving...">Rename</.button>
          </.form>

          <.form
            :if={@assignable_tasks != []}
            for={to_form(%{})}
            id={"bind-form-#{link.id}"}
            phx-submit="bind"
            phx-value-id={link.id}
            class="mt-2 flex items-end gap-2"
          >
            <.input
              name="task_id"
              value=""
              type="select"
              label="Bind a task"
              options={Enum.map(@assignable_tasks, &{&1.name, &1.id})}
              prompt="Choose a task"
            />
            <.button phx-disable-with="Binding...">Bind</.button>
          </.form>
        </div>
      </div>

      <p :if={@links == []} class="mt-4 opacity-70">No links yet. Create one to get a tag URL.</p>
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
     |> load(scope)}
  end

  @impl true
  def handle_event("create", _params, socket) do
    scope = socket.assigns.current_scope

    case Links.create_link(scope) do
      {:ok, _link} -> {:noreply, socket |> put_flash(:info, "Link created.") |> load(scope)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Could not create a link.")}
    end
  end

  def handle_event("rename", %{"id" => id, "label" => label}, socket) do
    scope = socket.assigns.current_scope
    link = Links.get_link!(scope, id)

    case Links.update_link(scope, link, %{"label" => label}) do
      {:ok, _link} -> {:noreply, socket |> put_flash(:info, "Link renamed.") |> load(scope)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Could not rename that link.")}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    link = Links.get_link!(scope, id)
    {:ok, _} = Links.delete_link(scope, link)
    {:noreply, socket |> put_flash(:info, "Link deleted.") |> load(scope)}
  end

  def handle_event("copied", _params, socket) do
    {:noreply, put_flash(socket, :info, "Link copied.")}
  end

  def handle_event("bind", %{"id" => id, "task_id" => task_id}, socket) when task_id != "" do
    scope = socket.assigns.current_scope
    link = Links.get_link!(scope, id)

    case Links.bind_task(scope, link, task_id) do
      {:ok, _} -> {:noreply, socket |> put_flash(:info, "Task bound.") |> load(scope)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Could not bind that task.")}
    end
  end

  def handle_event("bind", _params, socket), do: {:noreply, socket}

  def handle_event("unbind", %{"id" => binding_id}, socket) do
    scope = socket.assigns.current_scope
    {:ok, _} = Links.unbind_task(scope, binding_id)
    {:noreply, socket |> put_flash(:info, "Task unbound.") |> load(scope)}
  end

  defp load(socket, scope) do
    links = Links.list_links_with_tasks(scope)

    socket
    |> assign(:links, links)
    |> assign(:assignable_tasks, Tasks.list_tasks(scope))
    |> assign(:forms, Map.new(links, &{&1.id, to_form(%{"label" => &1.label})}))
  end

  defp bound_tasks(link), do: Enum.map(link.link_tasks, & &1.task)

  defp binding_id(link, task) do
    Enum.find(link.link_tasks, &(&1.task_id == task.id)).id
  end

  defp form_for(forms, link), do: Map.fetch!(forms, link.id)

  defp link_url(link), do: DoneManagerWeb.Endpoint.url() <> ~p"/links/#{link.id}"
end
