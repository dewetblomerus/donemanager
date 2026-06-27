defmodule DoneManager.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :auth0_sub, :string, null: false
      add :email, :string, null: false
      add :display_name, :string
      add :quiet_hours_start, :time
      add :quiet_hours_end, :time

      timestamps()
    end

    create unique_index(:users, [:auth0_sub])
    create unique_index(:users, [:email])
  end
end
