defmodule DoneManager.Households.Household do
  @moduledoc "A household owns tasks, tags, and members."

  use DoneManager.Schema
  import Ecto.Changeset

  alias DoneManager.Households.HouseholdInvitation
  alias DoneManager.Households.HouseholdMembership

  schema "households" do
    field :name, :string
    field :timezone, :string, default: "Etc/UTC"

    has_many :memberships, HouseholdMembership
    has_many :members, through: [:memberships, :user]
    has_many :invitations, HouseholdInvitation

    timestamps()
  end

  @doc false
  def changeset(household, attrs) do
    household
    |> cast(attrs, [:name, :timezone])
    |> validate_required([:name, :timezone])
    |> validate_inclusion(:timezone, DoneManager.Timezones.all())
  end
end
