defmodule DoneManager.Tasks.TaskEvent do
  @moduledoc """
  An append-only fact about an occurrence: `completed`,
  `duplicate_completion_attempted`, and others. Occurrence status is derived by
  folding these. Acknowledgements are events too, not a separate table. See
  architecture/database.md.
  """

  use DoneManager.Schema
  import Ecto.Changeset

  alias DoneManager.Accounts.User
  alias DoneManager.Automation.AutomationCommand
  alias DoneManager.Automation.NfcTag
  alias DoneManager.Integrations.BearerToken
  alias DoneManager.Tasks.TaskOccurrence

  @event_types ~w(completed duplicate_completion_attempted timer_started timer_cancelled
                  acknowledged reminder_sent skipped)
  @sources ~w(nfc web system)

  schema "task_events" do
    field :event_type, :string
    field :source, :string
    field :occurred_at, :utc_datetime_usec

    belongs_to :task_occurrence, TaskOccurrence
    belongs_to :user, User
    belongs_to :nfc_tag, NfcTag
    belongs_to :automation_command, AutomationCommand
    belongs_to :integration_bearer_token, BearerToken

    timestamps(updated_at: false)
  end

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:event_type, :source, :occurred_at])
    |> validate_required([:event_type, :source, :occurred_at])
    |> validate_inclusion(:event_type, @event_types)
    |> validate_inclusion(:source, @sources)
  end

  def event_types, do: @event_types
end
