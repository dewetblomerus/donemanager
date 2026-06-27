defmodule DoneManagerWeb.HouseholdLive.Form do
  use DoneManagerWeb, :live_view

  alias DoneManager.Households

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>New household</.header>

      <.form for={@form} id="household-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:name]} type="text" label="Name" />
        <.input field={@form[:timezone]} type="text" label="Timezone" />
        <footer class="mt-4 flex gap-2">
          <.button variant="primary" phx-disable-with="Saving...">Save household</.button>
          <.button navigate={~p"/households"}>Cancel</.button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :form, to_form(Households.change_household()))}
  end

  @impl true
  def handle_event("validate", %{"household" => params}, socket) do
    changeset = Households.change_household(%DoneManager.Households.Household{}, params)
    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"household" => params}, socket) do
    case Households.create_household(socket.assigns.current_scope, params) do
      {:ok, household} ->
        {:noreply,
         socket
         |> put_flash(:info, "Household created.")
         |> push_navigate(to: ~p"/households/#{household}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, action: :insert))}
    end
  end
end
