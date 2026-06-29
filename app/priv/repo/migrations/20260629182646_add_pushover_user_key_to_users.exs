defmodule DoneManager.Repo.Migrations.AddPushoverUserKeyToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :pushover_user_key, :binary
    end
  end
end
