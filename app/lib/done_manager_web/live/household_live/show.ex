defmodule DoneManagerWeb.HouseholdLive.Show do
  use DoneManagerWeb, :live_view

  alias DoneManager.Accounts.Scope
  alias DoneManager.Households

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@household.name}
        <:subtitle>Timezone: {@household.timezone}</:subtitle>
        <:actions>
          <.button variant="primary" navigate={~p"/households/#{@household}/tasks"}>Tasks</.button>
          <.button navigate={~p"/households"}>Back</.button>
        </:actions>
      </.header>

      <.header>Members</.header>
      <.table id="members" rows={@memberships}>
        <:col :let={membership} label="Email">{membership.user.email}</:col>
        <:col :let={membership} label="Role">{membership.role}</:col>
      </.table>

      <section :if={@owner?} class="mt-8">
        <.header>Invite by email</.header>
        <.form for={@invite_form} id="invite-form" phx-submit="invite">
          <.input field={@invite_form[:invitee_email]} type="email" label="Email" />
          <footer class="mt-4">
            <.button variant="primary" phx-disable-with="Inviting...">Send invite</.button>
          </footer>
        </.form>

        <.header>Pending invitations</.header>
        <.table id="invitations" rows={@invitations}>
          <:col :let={invitation} label="Email">{invitation.invitee_email}</:col>
          <:col :let={invitation} label="Status">{invitation.status}</:col>
        </.table>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    household = Households.get_household!(socket.assigns.current_scope, id)
    scope = Scope.put_household(socket.assigns.current_scope, household)

    {:ok,
     socket
     |> assign(:current_scope, scope)
     |> assign(:household, household)
     |> assign(:invite_form, to_form(Households.change_invitation()))
     |> load_household(scope)}
  end

  @impl true
  def handle_event("invite", %{"household_invitation" => params}, socket) do
    case Households.invite_by_email(socket.assigns.current_scope, params) do
      {:ok, _invitation} ->
        {:noreply,
         socket
         |> put_flash(:info, "Invitation sent.")
         |> assign(:invite_form, to_form(Households.change_invitation()))
         |> load_household(socket.assigns.current_scope)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :invite_form, to_form(changeset, action: :insert))}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Only an owner can invite members.")}
    end
  end

  defp load_household(socket, scope) do
    socket
    |> assign(:memberships, Households.list_memberships(scope))
    |> assign(:owner?, Households.owner?(scope))
    |> assign(:invitations, Households.list_invitations(scope))
  end
end
