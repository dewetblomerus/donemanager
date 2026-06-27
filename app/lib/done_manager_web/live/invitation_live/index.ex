defmodule DoneManagerWeb.InvitationLive.Index do
  use DoneManagerWeb, :live_view

  alias DoneManager.Households

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>Your invitations</.header>

      <.table id="invitations" rows={@invitations}>
        <:col :let={invitation} label="Household">{invitation.household.name}</:col>
        <:action :let={invitation}>
          <.button variant="primary" phx-click="accept" phx-value-id={invitation.id}>
            Accept
          </.button>
        </:action>
      </.table>

      <p :if={@invitations == []} class="mt-4 opacity-70">No pending invitations.</p>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, load_invitations(socket)}
  end

  @impl true
  def handle_event("accept", %{"id" => id}, socket) do
    case Households.accept_invitation(socket.assigns.current_scope.user, id) do
      {:ok, _membership} ->
        {:noreply,
         socket
         |> put_flash(:info, "Invitation accepted.")
         |> push_navigate(to: ~p"/households")}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "That invitation is no longer valid.")
         |> load_invitations()}
    end
  end

  defp load_invitations(socket) do
    invitations =
      Households.list_pending_invitations_for_user(socket.assigns.current_scope.user)

    assign(socket, :invitations, invitations)
  end
end
