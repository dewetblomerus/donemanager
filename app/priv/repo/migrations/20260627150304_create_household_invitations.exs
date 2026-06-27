defmodule DoneManager.Repo.Migrations.CreateHouseholdInvitations do
  use Ecto.Migration

  def change do
    create table(:household_invitations) do
      add :household_id, references(:households, type: :uuid, on_delete: :delete_all), null: false
      add :inviter_id, references(:users, type: :uuid, on_delete: :nilify_all)
      add :invitee_email, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :expires_at, :utc_datetime_usec

      timestamps()
    end

    create index(:household_invitations, [:household_id])

    create unique_index(:household_invitations, [:household_id, :invitee_email],
             where: "status = 'pending'",
             name: :household_invitations_pending_unique
           )
  end
end
