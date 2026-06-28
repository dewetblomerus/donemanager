defmodule DoneManager.Links.Link do
  @moduledoc """
  A stable, public deep-link target owned by a household — a physical NFC tag
  today, a printed QR code or a bookmark tomorrow. It carries no secret.

  The row's UUIDv7 primary key is the id baked into the tag URL (`/links/{id}`),
  minted by the web UI and fixed forever so the physical tag never has to be
  rewritten. `label` is the human name; `active` allows retiring a link. See
  architecture/database.md.
  """

  use DoneManager.Schema
  import Ecto.Changeset

  alias DoneManager.Households.Household
  alias DoneManager.Links.LinkTask

  schema "links" do
    field :label, :string
    field :active, :boolean, default: true

    belongs_to :household, Household
    has_many :link_tasks, LinkTask

    timestamps()
  end

  @doc false
  def changeset(link, attrs) do
    link
    |> cast(attrs, [:label, :active])
    |> unique_constraint(:id, name: :links_pkey)
  end
end
