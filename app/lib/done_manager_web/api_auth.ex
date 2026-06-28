defmodule DoneManagerWeb.ApiAuth do
  @moduledoc """
  Access-token authentication for the integration API.

  Pulls the token from the POST body `access_token` param, resolves it to a non-revoked
  `BearerToken` (with its household), and assigns it as `:current_token`. A
  missing, malformed, or revoked token halts with `401` per architecture/api.md.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias DoneManager.Integrations

  def require_access_token(conn, _opts) do
    with %{"access_token" => token} when is_binary(token) <- conn.body_params,
         {:ok, bearer_token} <- Integrations.authenticate(token) do
      assign(conn, :current_token, bearer_token)
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{errors: %{detail: "Unauthorized"}})
        |> halt()
    end
  end
end
