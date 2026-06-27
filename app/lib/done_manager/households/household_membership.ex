defmodule DoneManager.Households.HouseholdMembership do
  @moduledoc "Joins a user to a household with a role."

  use DoneManager.Schema
  import Ecto.Changeset

  alias DoneManager.Accounts.User
  alias DoneManager.Households.Household

  @roles ~w(owner member)

  schema "household_memberships" do
    field :role, :string, default: "member"

    belongs_to :household, Household
    belongs_to :user, User

    timestamps()
  end

  @doc false
  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:household_id, :user_id, :role])
    |> validate_required([:household_id, :user_id, :role])
    |> validate_inclusion(:role, @roles)
    |> unique_constraint([:household_id, :user_id])
  end

  def roles, do: @roles
end
