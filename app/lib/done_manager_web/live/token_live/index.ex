defmodule DoneManagerWeb.TokenLive.Index do
  use DoneManagerWeb, :live_view

  alias DoneManager.Accounts.Scope
  alias DoneManager.Households
  alias DoneManager.Integrations

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        API tokens for {@household.name}
        <:subtitle>
          A token authenticates a scanning device. It belongs to a member, so scans are attributed to them.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/households/#{@household}"}>Back</.button>
        </:actions>
      </.header>

      <div
        :if={@new_plaintext}
        id="new-token"
        class="mt-4 rounded-lg border border-success p-4"
      >
        <p class="font-semibold">Token created — copy it now. It won't be shown again.</p>
        <pre class="mt-2 overflow-x-auto rounded bg-base-200 p-2 text-sm">{@new_plaintext}</pre>
      </div>

      <section :if={@owner?} class="mt-8">
        <.header>New token</.header>
        <.form for={@form} id="token-form" phx-submit="create">
          <.input field={@form[:label]} type="text" label="Label (e.g. Kitchen phone)" />
          <.input
            field={@form[:user_id]}
            type="select"
            label="Belongs to"
            options={@member_options}
          />
          <footer class="mt-4">
            <.button variant="primary" phx-disable-with="Creating...">Create token</.button>
          </footer>
        </.form>
      </section>

      <.header>Existing tokens</.header>
      <.table id="tokens" rows={@tokens}>
        <:col :let={token} label="Label">{token.label || "—"}</:col>
        <:col :let={token} label="Prefix">{token.prefix}…</:col>
        <:col :let={token} label="Belongs to">{token.user && token.user.email}</:col>
        <:col :let={token} label="Status">{if token.revoked_at, do: "revoked", else: "active"}</:col>
        <:action :let={token}>
          <.link
            :if={@owner? && is_nil(token.revoked_at)}
            phx-click="revoke"
            phx-value-id={token.id}
            data-confirm="Revoke this token? Devices using it stop working immediately."
            class="link"
          >
            Revoke
          </.link>
        </:action>
      </.table>
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
     |> assign(:owner?, Households.owner?(scope))
     |> assign(:new_plaintext, nil)
     |> assign(:member_options, member_options(scope))
     |> assign(:form, to_form(%{"label" => nil, "user_id" => scope.user.id}, as: :token))
     |> load_tokens(scope)}
  end

  @impl true
  def handle_event("create", %{"token" => params}, socket) do
    scope = socket.assigns.current_scope
    attrs = %{label: params["label"], user_id: params["user_id"]}

    case Integrations.create_token(scope, attrs) do
      {:ok, _token, plaintext} ->
        {:noreply,
         socket
         |> put_flash(:info, "Token created.")
         |> assign(:new_plaintext, plaintext)
         |> assign(:form, to_form(%{"label" => nil, "user_id" => scope.user.id}, as: :token))
         |> load_tokens(scope)}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Only an owner can create tokens.")}

      {:error, :not_a_member} ->
        {:noreply, put_flash(socket, :error, "That user is not a member of this household.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not create the token.")}
    end
  end

  def handle_event("revoke", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope

    case Integrations.revoke_token(scope, id) do
      {:ok, _token} ->
        {:noreply, socket |> put_flash(:info, "Token revoked.") |> load_tokens(scope)}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Only an owner can revoke tokens.")}
    end
  end

  defp load_tokens(socket, scope),
    do: assign(socket, :tokens, Integrations.list_tokens(scope))

  defp member_options(scope) do
    scope
    |> Households.list_memberships()
    |> Enum.map(&{&1.user.email, &1.user.id})
  end
end
