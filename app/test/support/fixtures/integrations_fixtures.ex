defmodule DoneManager.IntegrationsFixtures do
  @moduledoc "Test fixtures for the Integrations context."

  alias DoneManager.Accounts.Scope
  alias DoneManager.Integrations

  @doc "Mints a bearer token for the scope's household; returns `{token, plaintext}`."
  def token_fixture(%Scope{} = scope, attrs \\ %{}) do
    {:ok, token, plaintext} = Integrations.create_token(scope, Enum.into(attrs, %{}))
    {token, plaintext}
  end
end
