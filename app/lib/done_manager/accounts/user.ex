defmodule DoneManager.Accounts.User do
  @moduledoc "A person who authenticates through Auth0."

  use DoneManager.Schema
  import Ecto.Changeset

  alias DoneManager.Households.HouseholdMembership

  schema "users" do
    field :auth0_sub, :string
    field :email, :string
    field :display_name, :string
    field :quiet_hours_start, :time
    field :quiet_hours_end, :time

    has_many :memberships, HouseholdMembership
    has_many :households, through: [:memberships, :household]

    timestamps()
  end

  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:auth0_sub, :email, :display_name, :quiet_hours_start, :quiet_hours_end])
    |> validate_required([:auth0_sub, :email])
    |> unique_constraint(:auth0_sub)
    |> unique_constraint(:email)
  end
end
