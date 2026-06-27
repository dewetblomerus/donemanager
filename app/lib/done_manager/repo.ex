defmodule DoneManager.Repo do
  use Ecto.Repo,
    otp_app: :done_manager,
    adapter: Ecto.Adapters.Postgres
end
