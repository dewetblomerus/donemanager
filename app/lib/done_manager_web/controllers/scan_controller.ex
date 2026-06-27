defmodule DoneManagerWeb.ScanController do
  @moduledoc """
  The NFC scan endpoint: `POST /v1/tags/:external_id/scans`.

  The token is authenticated by `DoneManagerWeb.ApiAuth` upstream; this action
  resolves the tag against the token's household and returns the outcome. Every
  valid scan is `200` with the result in `outcome`. See architecture/api.md.
  """

  use DoneManagerWeb, :controller

  alias DoneManager.Automation

  def create(conn, %{"external_id" => external_id}) do
    case Automation.handle_scan(conn.assigns.current_token, external_id) do
      {:ok, outcome} ->
        json(conn, outcome)

      {:error, :malformed_external_id} ->
        conn
        |> put_status(:bad_request)
        |> json(%{errors: %{detail: "Malformed external_id"}})
    end
  end
end
