defmodule DoneManager.Households.HouseholdInvitation do
  @moduledoc """
  An invite to a household, targeting an email that may not have a user yet.
  No email is sent in V1; the invitee sees it in-app after signing up.
  """

  use DoneManager.Schema
  import Ecto.Changeset

  alias DoneManager.Accounts.User
  alias DoneManager.Households.Household

  @statuses ~w(pending accepted expired)

  schema "household_invitations" do
    field :invitee_email, :string
    field :status, :string, default: "pending"
    field :expires_at, :utc_datetime_usec

    belongs_to :household, Household
    belongs_to :inviter, User

    timestamps()
  end

  @doc false
  def changeset(invitation, attrs) do
    invitation
    |> cast(attrs, [:household_id, :inviter_id, :invitee_email, :status, :expires_at])
    |> validate_required([:household_id, :invitee_email, :status])
    |> update_change(:invitee_email, &normalize_email/1)
    |> validate_format(:invitee_email, ~r/^[^\s]+@[^\s]+$/)
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint([:household_id, :invitee_email],
      name: :household_invitations_pending_unique,
      message: "already has a pending invite"
    )
  end

  defp normalize_email(email) when is_binary(email),
    do: email |> String.trim() |> String.downcase()

  defp normalize_email(email), do: email

  def statuses, do: @statuses
end
