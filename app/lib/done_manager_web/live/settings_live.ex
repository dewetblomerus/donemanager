defmodule DoneManagerWeb.SettingsLive do
  use DoneManagerWeb, :live_view

  alias DoneManager.Accounts
  alias DoneManager.Pushover

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>Settings</.header>

      <.form for={@form} id="settings-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:display_name]} type="text" label="Display name" />
        <.input field={@form[:quiet_hours_start]} type="time" label="Quiet hours start" />
        <.input field={@form[:quiet_hours_end]} type="time" label="Quiet hours end" />
        <.input
          field={@form[:pushover_user_key]}
          type="text"
          label="Pushover user key"
          phx-debounce="blur"
        />
        <footer class="mt-4 flex gap-2">
          <.button variant="primary" phx-disable-with="Saving...">Save settings</.button>
          <.button
            :if={@has_pushover_key}
            type="button"
            phx-click="test"
            phx-disable-with="Sending..."
          >
            Send test notification
          </.button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    {:ok,
     socket
     |> assign(:has_pushover_key, present?(user.pushover_user_key))
     |> assign(:form, to_form(Accounts.change_user_settings(user)))}
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    changeset = Accounts.change_user_settings(socket.assigns.current_scope.user, params)
    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"user" => params}, socket) do
    case Accounts.update_user_settings(socket.assigns.current_scope.user, params) do
      {:ok, user} ->
        scope = %{socket.assigns.current_scope | user: user}

        {:noreply,
         socket
         |> assign(:current_scope, scope)
         |> assign(:has_pushover_key, present?(user.pushover_user_key))
         |> assign(:form, to_form(Accounts.change_user_settings(user)))
         |> put_flash(:info, "Settings saved.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, action: :update))}
    end
  end

  def handle_event("test", _params, socket) do
    user = socket.assigns.current_scope.user

    flash =
      case Pushover.send_message(user.pushover_user_key, "Test from Done Manager") do
        :ok -> {:info, "Test notification sent."}
        {:error, _reason} -> {:error, "Could not send test notification."}
      end

    {:noreply, put_flash(socket, elem(flash, 0), elem(flash, 1))}
  end

  defp present?(value), do: is_binary(value) and value != ""
end
