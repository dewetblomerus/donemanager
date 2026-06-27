defmodule DoneManager.Automation do
  @moduledoc """
  NFC tags, the commands that bind a tag to a task, and the scan resolution that
  ties them together.

  Web functions take a `%Scope{}` and only touch the scope's household. The scan
  path is keyed on the authenticating token's household instead — that household
  is the tenant boundary, so cross-household access stays structurally
  impossible. See architecture/api.md and architecture/database.md.
  """

  import Ecto.Query, warn: false

  alias DoneManager.Accounts.Scope
  alias DoneManager.Automation.AutomationCommand
  alias DoneManager.Automation.NfcTag
  alias DoneManager.Households.Household
  alias DoneManager.Integrations.BearerToken
  alias DoneManager.Repo
  alias DoneManager.Tasks
  alias DoneManager.Tasks.Task

  ## Tags and commands (web, scope-keyed)

  @doc "Tags in the scope's current household, newest first."
  def list_tags(%Scope{household: %Household{id: household_id}}) do
    from(t in NfcTag, where: t.household_id == ^household_id, order_by: [desc: t.inserted_at])
    |> Repo.all()
  end

  @doc "Tags in the household with no active command, available to assign."
  def list_unassigned_tags(%Scope{household: %Household{id: household_id}}) do
    assigned = from(c in AutomationCommand, where: c.active, select: c.nfc_tag_id)

    from(t in NfcTag, where: t.household_id == ^household_id and t.id not in subquery(assigned))
    |> Repo.all()
  end

  @doc "Assigns a tag to a task as an `attempt_completion` command (owner-scoped task)."
  def assign_tag(%Scope{household: %Household{id: household_id}}, %Task{} = task, tag_id) do
    %AutomationCommand{
      household_id: household_id,
      task_id: task.id,
      nfc_tag_id: tag_id
    }
    |> AutomationCommand.changeset(%{command_type: "attempt_completion", label: task.name})
    |> Repo.insert()
  end

  @doc "Active commands for a task, with their tag preloaded."
  def list_commands_for_task(%Task{id: task_id}) do
    from(c in AutomationCommand,
      where: c.task_id == ^task_id and c.active,
      preload: [:nfc_tag]
    )
    |> Repo.all()
  end

  ## Scan (integration, token-keyed)

  @doc """
  Resolves and executes a scan for an authenticated token. Returns
  `{:ok, outcome}` where `outcome` is a map ready for the API response, or
  `{:error, :malformed_external_id}`. See the contract in architecture/api.md.
  """
  def handle_scan(%BearerToken{household: %Household{id: household_id}} = token, external_id) do
    if valid_uuid?(external_id) do
      {state, tag} = find_or_create_tag(household_id, external_id)
      {:ok, resolve(state, tag, token)}
    else
      {:error, :malformed_external_id}
    end
  end

  defp resolve(:created, _tag, _token) do
    %{
      outcome: "tag_registered",
      message: "New tag registered. Assign it to a task in the web app.",
      task: nil,
      occurrence_status: nil
    }
  end

  defp resolve(:existing, tag, token) do
    case active_command(tag) do
      nil ->
        %{
          outcome: "tag_unassigned",
          message: "This tag is not assigned to a task yet. Assign it in the web app.",
          task: nil,
          occurrence_status: nil
        }

      %AutomationCommand{command_type: "attempt_completion", task: task} = command ->
        attempt_completion(task, tag, command, token)

      _other ->
        %{
          outcome: "tag_unassigned",
          message: "This tag's command is not supported yet.",
          task: nil,
          occurrence_status: nil
        }
    end
  end

  defp attempt_completion(%Task{} = task, tag, command, token) do
    occurrence = Tasks.current_occurrence(task)

    attribution = %{
      source: "nfc",
      user_id: token.user_id,
      nfc_tag_id: tag.id,
      automation_command_id: command.id,
      integration_bearer_token_id: token.id
    }

    {outcome, _event} = Tasks.attempt_completion(occurrence, attribution)
    completion = Tasks.completion_event(occurrence)

    %{
      outcome: Atom.to_string(outcome),
      message: completion_message(task, outcome),
      task: task.name,
      occurrence_status: occurrence_status(completion)
    }
  end

  defp completion_message(%Task{name: name}, :completed), do: "#{name} marked done."

  defp completion_message(%Task{name: name}, :duplicate_completion_attempted),
    do: "#{name} was already done."

  defp occurrence_status(nil), do: nil

  defp occurrence_status(event) do
    %{
      "done_by" => event.user && (event.user.display_name || event.user.email),
      "done_at" => DateTime.to_iso8601(event.occurred_at)
    }
  end

  defp active_command(%NfcTag{id: tag_id}) do
    from(c in AutomationCommand,
      where: c.nfc_tag_id == ^tag_id and c.active,
      preload: [:task]
    )
    |> Repo.one()
  end

  defp find_or_create_tag(household_id, external_id) do
    now = DateTime.utc_now()

    case Repo.get_by(NfcTag, household_id: household_id, external_id: external_id) do
      nil ->
        %NfcTag{household_id: household_id}
        |> NfcTag.changeset(%{external_id: external_id, last_scanned_at: now})
        |> Repo.insert()
        |> case do
          {:ok, tag} ->
            {:created, tag}

          # Lost the find-or-create race; the row now exists.
          {:error, _changeset} ->
            {:existing,
             touch_tag(
               Repo.get_by!(NfcTag, household_id: household_id, external_id: external_id),
               now
             )}
        end

      tag ->
        {:existing, touch_tag(tag, now)}
    end
  end

  defp touch_tag(tag, now) do
    {:ok, tag} = tag |> NfcTag.changeset(%{last_scanned_at: now}) |> Repo.update()
    tag
  end

  defp valid_uuid?(value) when is_binary(value), do: match?({:ok, _}, Ecto.UUID.cast(value))
  defp valid_uuid?(_), do: false
end
