defmodule DoneManagerWeb.HouseholdLive.Index do
  use DoneManagerWeb, :live_view

  alias DoneManager.Households

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Your households
        <:actions>
          <.button variant="primary" navigate={~p"/households/new"}>
            <.icon name="hero-plus" /> New household
          </.button>
        </:actions>
      </.header>

      <.table
        id="households"
        rows={@households}
        row_click={fn household -> JS.navigate(~p"/households/#{household}") end}
      >
        <:col :let={household} label="Name">{household.name}</:col>
        <:col :let={household} label="Timezone">{household.timezone}</:col>
      </.table>

      <p :if={@households == []} class="mt-4 opacity-70">
        You have no households yet. Create one, or check your <.link
          navigate={~p"/invitations"}
          class="link"
        >invitations</.link>.
      </p>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :households, Households.list_households(socket.assigns.current_scope))}
  end
end
