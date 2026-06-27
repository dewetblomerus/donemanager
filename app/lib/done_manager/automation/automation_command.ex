defmodule DoneManager.Automation.AutomationCommand do
  @moduledoc """
  Maps a tag input to task-specific intent. The Stage 2 slice supports
  `attempt_completion`; `toggle_timer` arrives later. One active command per tag
  resolves a scan unambiguously. See architecture/database.md.
  """

  use DoneManager.Schema
  import Ecto.Changeset

  alias DoneManager.Automation.NfcTag
  alias DoneManager.Households.Household
  alias DoneManager.Tasks.Task

  @command_types ~w(attempt_completion toggle_timer)

  schema "automation_commands" do
    field :label, :string
    field :command_type, :string
    field :config, :map, default: %{}
    field :active, :boolean, default: true

    belongs_to :household, Household
    belongs_to :task, Task
    belongs_to :nfc_tag, NfcTag

    timestamps()
  end

  @doc false
  def changeset(command, attrs) do
    command
    |> cast(attrs, [:label, :command_type, :config, :active])
    |> validate_required([:command_type])
    |> validate_inclusion(:command_type, @command_types)
    |> unique_constraint(:nfc_tag_id,
      name: :automation_commands_active_tag_unique,
      message: "tag already has an active command"
    )
  end

  def command_types, do: @command_types
end
