defmodule DoneManager.Automation.NfcTag do
  @moduledoc """
  A physical input owned by a household, not a task. The scan sends an opaque
  client-generated `external_id` (a UUIDv7 written onto the tag); the first scan
  of an unknown id provisions the row active and unassigned. Human naming lives
  in `label`. See architecture/database.md and architecture/api.md.
  """

  use DoneManager.Schema
  import Ecto.Changeset

  alias DoneManager.Automation.AutomationCommand
  alias DoneManager.Households.Household

  schema "nfc_tags" do
    field :label, :string
    field :external_id, :string
    field :active, :boolean, default: true
    field :last_scanned_at, :utc_datetime_usec

    belongs_to :household, Household
    has_many :automation_commands, AutomationCommand

    timestamps()
  end

  @doc false
  def changeset(tag, attrs) do
    tag
    |> cast(attrs, [:label, :external_id, :active, :last_scanned_at])
    |> validate_required([:external_id])
    |> unique_constraint([:household_id, :external_id])
  end
end
