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

      <section
        id="tag-registration-instructions"
        class="mb-6 rounded-lg border border-base-300 bg-base-200/60 p-4 shadow-sm"
      >
        <div class="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
          <div class="max-w-2xl">
            <div class="flex items-center gap-2">
              <.icon name="hero-sparkles" class="size-5 text-primary" />
              <h2 class="font-semibold">Add a tag</h2>
            </div>
            <p class="mt-2 text-sm text-base-content/70">
              Write this URL to an NFC tag or call it from a scanning device. The UUIDv7 in the
              path is the tag's unique id, and the first authenticated POST registers it here.
            </p>
          </div>

          <button
            id="copy-tag-registration-url"
            type="button"
            phx-click={JS.dispatch("dm:copy-to-clipboard", detail: %{text: @registration_url})}
            class="btn btn-primary transition-transform duration-150 hover:-translate-y-0.5"
          >
            <.icon name="hero-clipboard-document" class="size-4" /> Copy URL
          </button>
        </div>

        <label class="mt-4 block rounded-lg border border-base-300 bg-base-100 p-3">
          <span class="text-xs font-semibold uppercase tracking-wide text-base-content/60">
            POST URL
          </span>
          <input
            id="tag-registration-url"
            type="url"
            value={@registration_url}
            readonly
            class="mt-2 w-full bg-transparent text-sm outline-none"
          />
        </label>

        <ol class="mt-4 grid gap-3 text-sm text-base-content/75 md:grid-cols-3">
          <li class="rounded-lg border border-base-300 bg-base-100 p-3">
            <span class="font-semibold text-base-content">1. Copy</span> the URL above.
          </li>
          <li class="rounded-lg border border-base-300 bg-base-100 p-3">
            <span class="font-semibold text-base-content">2. Save</span> it on the tag or scanner.
          </li>
          <li class="rounded-lg border border-base-300 bg-base-100 p-3">
            <span class="font-semibold text-base-content">3. POST</span>
            with an API token bearer header.
          </li>
        </ol>
      </section>

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
            <span :if={tag.last_scanned_at && tag.last_scanned_by}>
              by {scanner_name(tag.last_scanned_by)}
            </span>
            <span :if={tag.last_scanned_at && is_nil(tag.last_scanned_by)}>
              by a shared device
            </span>
            <%= case assignment(tag) do %>
              <% nil -> %>
                · <span class="opacity-80">unassigned</span>
              <% task -> %>
                · assigned to <.link navigate={~p"/tasks/#{task}"} class="link">{task.name}</.link>
            <% end %>
          </p>

          <.form
            for={tag_form(@tag_forms, tag)}
            id={"tag-form-#{tag.id}"}
            phx-submit="rename"
            phx-value-id={tag.id}
            class="mt-2 flex items-end gap-2"
          >
            <.input field={tag_form(@tag_forms, tag)[:label]} type="text" placeholder="Name this tag" />
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
     |> assign_registration_url()
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

  defp load_tags(socket, scope) do
    tags = Automation.list_tags_with_assignment(scope)

    socket
    |> assign(:tags, tags)
    |> assign(:tag_forms, Map.new(tags, &{&1.id, to_form(%{"label" => &1.label})}))
  end

  defp assignment(tag) do
    case tag.automation_commands do
      [command | _] -> command.task
      _ -> nil
    end
  end

  defp tag_form(forms, tag), do: Map.fetch!(forms, tag.id)

  defp assign_registration_url(socket) do
    external_id = UUIDv7.generate()
    path = ~p"/v1/tags/#{external_id}/scans"

    assign(socket, :registration_url, DoneManagerWeb.Endpoint.url() <> path)
  end

  defp delete_confirm(tag) do
    base = "Delete this tag? Scanning it again will re-register it."

    case assignment(tag) do
      nil -> base
      task -> "#{base} It is assigned to \"#{task.name}\"; that assignment will be removed."
    end
  end

  defp scanner_name(user), do: user.display_name || user.email

  defp format_time(nil), do: "never"
  defp format_time(dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")
end
