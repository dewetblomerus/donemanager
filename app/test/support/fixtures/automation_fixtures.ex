defmodule DoneManager.AutomationFixtures do
  @moduledoc "Test fixtures for the Automation context."

  alias DoneManager.Accounts.Scope
  alias DoneManager.Automation.NfcTag
  alias DoneManager.Repo
  alias DoneManager.Tasks.Task

  @doc "A registered nfc_tag in the scope's household."
  def tag_fixture(%Scope{household: household}, attrs \\ %{}) do
    attrs = Enum.into(attrs, %{external_id: UUIDv7.generate(), label: "Kitchen"})

    %NfcTag{household_id: household.id}
    |> NfcTag.changeset(attrs)
    |> Repo.insert!()
  end

  @doc "Assigns `tag` to `task` as an attempt_completion command."
  def command_fixture(%Scope{} = scope, %Task{} = task, %NfcTag{} = tag) do
    {:ok, command} = DoneManager.Automation.assign_tag(scope, task, tag.id)
    command
  end
end
