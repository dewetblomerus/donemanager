defmodule DoneManagerWeb.TagLive.Index do
  use DoneManagerWeb, :live_view

  alias DoneManager.Accounts.Scope
  alias DoneManager.Automation
  alias DoneManager.Households

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        NFC tags in {@household.name}
        <:subtitle>
          Tags register themselves the first time they're scanned. Rename one here, then assign it to a task.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/households/#{@household}"}>Back</.button>
        </:actions>
      </.header>

      <div id="tags" class="space-y-3">
        <div :for={tag <- @tags} id={"tag-#{tag.id}"} class="rounded-lg border border-base-300 p-4">
          <div class="flex items-start justify-between gap-4">
            <p class="font-semibold">{tag.label || "Unnamed tag"}</p>
            <.link
              phx-click="delete"
              phx-value-id={tag.id}
              data-confirm={delete_confirm(tag)}
              class="link text-error"
            >
              Delete
            </.link>
          </div>
          <p class="text-sm opacity-60">{tag.external_id}</p>
          <p class="text-sm opacity-60">
            Last scanned: {format_time(tag.last_scanned_at)}
            <%= case assignment(tag) do %>
              <% nil -> %>
                · <span class="opacity-80">unassigned</span>
              <% task -> %>
                · assigned to <.link navigate={~p"/tasks/#{task}"} class="link">{task.name}</.link>
            <% end %>
          </p>

          <.form
            :let={f}
            for={tag_form(tag)}
            id={"tag-form-#{tag.id}"}
            phx-submit="rename"
            phx-value-id={tag.id}
            class="mt-2 flex items-end gap-2"
          >
            <.input field={f[:label]} type="text" placeholder="Name this tag" />
            <.button variant="primary" phx-disable-with="Saving...">Rename</.button>
          </.form>
        </div>
      </div>

      <p :if={@tags == []} class="mt-4 opacity-70">
        No tags yet. Scan a tag with a valid token and it'll appear here.
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
     |> load_tags(scope)}
  end

  @impl true
  def handle_event("rename", %{"id" => id, "label" => label}, socket) do
    scope = socket.assigns.current_scope
    tag = Automation.get_tag!(scope, id)

    case Automation.update_tag(scope, tag, %{"label" => label}) do
      {:ok, _tag} ->
        {:noreply, socket |> put_flash(:info, "Tag renamed.") |> load_tags(scope)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not rename that tag.")}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    tag = Automation.get_tag!(scope, id)

    case Automation.delete_tag(scope, tag) do
      {:ok, _tag} ->
        {:noreply, socket |> put_flash(:info, "Tag deleted.") |> load_tags(scope)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete that tag.")}
    end
  end

  defp load_tags(socket, scope),
    do: assign(socket, :tags, Automation.list_tags_with_assignment(scope))

  defp assignment(tag) do
    case tag.automation_commands do
      [command | _] -> command.task
      _ -> nil
    end
  end

  defp tag_form(tag), do: to_form(%{"label" => tag.label})

  defp delete_confirm(tag) do
    base = "Delete this tag? Scanning it again will re-register it."

    case assignment(tag) do
      nil -> base
      task -> "#{base} It is assigned to \"#{task.name}\"; that assignment will be removed."
    end
  end

  defp format_time(nil), do: "never"
  defp format_time(dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")
end
