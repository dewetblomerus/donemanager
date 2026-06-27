defmodule DoneManager.Tasks do
  @moduledoc """
  Tasks, their occurrences, and the events that record what happened to them.

  Read/write functions take a `%Scope{}` and only ever touch the scope's
  household, so cross-household access is structurally impossible. Occurrence
  status is always derived from `task_events`, never stored. In the Stage 2
  slice a task is created with one eager occurrence; recurrence generation comes
  later with the reconcile loop. See architecture/stages.md.
  """

  import Ecto.Query, warn: false

  alias DoneManager.Accounts.Scope
  alias DoneManager.Accounts.User
  alias DoneManager.Households.Household
  alias DoneManager.Households.HouseholdMembership
  alias DoneManager.Repo
  alias DoneManager.Tasks.Task
  alias DoneManager.Tasks.TaskEvent
  alias DoneManager.Tasks.TaskOccurrence

  ## Tasks

  @doc "Tasks in the scope's current household, newest first."
  def list_tasks(%Scope{household: %Household{id: household_id}}) do
    from(t in Task, where: t.household_id == ^household_id, order_by: [desc: t.inserted_at])
    |> Repo.all()
  end

  @doc """
  Fetches a task by its (globally unique) id, but only if the scope's user is a
  member of the task's household, or raises (default-deny). Keyed on membership
  rather than the current household so a by-id route resolves the right
  household regardless of which one is currently selected.
  """
  def get_task!(%Scope{user: %User{id: user_id}}, id) do
    from(t in Task,
      join: m in HouseholdMembership,
      on: m.household_id == t.household_id,
      where: t.id == ^id and m.user_id == ^user_id
    )
    |> Repo.one!()
  end

  @doc """
  Creates a task in the scope's current household and eagerly generates its
  current occurrence, so the slice has something a scan can complete without a
  scheduler.
  """
  def create_task(%Scope{household: %Household{id: household_id}}, attrs) do
    Repo.transaction(fn ->
      task =
        %Task{household_id: household_id}
        |> Task.changeset(attrs)
        |> Repo.insert()
        |> unwrap()

      task |> insert_occurrence() |> unwrap()
      task
    end)
  end

  @doc "Updates a task. The task must already have been loaded through a scope."
  def update_task(%Scope{household: %Household{id: household_id}}, %Task{} = task, attrs) do
    if task.household_id == household_id do
      task |> Task.changeset(attrs) |> Repo.update()
    else
      {:error, :unauthorized}
    end
  end

  def change_task(%Task{} = task \\ %Task{}, attrs \\ %{}), do: Task.changeset(task, attrs)

  ## Occurrences

  @doc "The current (most recent) occurrence for a task, or nil."
  def current_occurrence(%Task{id: task_id}) do
    from(o in TaskOccurrence,
      where: o.task_id == ^task_id,
      order_by: [desc: o.inserted_at],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  The task's current occurrence, generating one if none exists. The eager
  occurrence makes this rare, but a scan must always have something to act on
  (and an interval task's completion rolls a fresh occurrence forward), so the
  scan path self-heals rather than failing.
  """
  def current_or_create_occurrence(%Task{} = task) do
    case current_occurrence(task) do
      nil -> task |> insert_occurrence() |> unwrap_occurrence()
      occurrence -> occurrence
    end
  end

  defp insert_occurrence(%Task{id: task_id}) do
    %TaskOccurrence{task_id: task_id}
    |> TaskOccurrence.changeset(%{occurrence_date: Date.utc_today(), due_at: DateTime.utc_now()})
    |> Repo.insert()
  end

  defp unwrap_occurrence({:ok, occurrence}), do: occurrence

  @doc "Whether an occurrence has been completed, derived from its events."
  def done?(%TaskOccurrence{id: occurrence_id}) do
    Repo.exists?(
      from e in TaskEvent,
        where: e.task_occurrence_id == ^occurrence_id and e.event_type == "completed"
    )
  end

  @doc "The `completed` event for an occurrence with its user preloaded, or nil."
  def completion_event(%TaskOccurrence{id: occurrence_id}) do
    from(e in TaskEvent,
      where: e.task_occurrence_id == ^occurrence_id and e.event_type == "completed",
      order_by: [asc: e.occurred_at],
      limit: 1,
      preload: [:user]
    )
    |> Repo.one()
  end

  @doc """
  Attempts to complete an occurrence. Records a `completed` event if it is still
  open, or a `duplicate_completion_attempted` event without undoing it if it was
  already done. `attribution` carries the actor keys (`user_id`, `nfc_tag_id`,
  `automation_command_id`, `integration_bearer_token_id`) and `source`.
  Returns `{outcome, event}` where outcome is `:completed` or
  `:duplicate_completion_attempted`.
  """
  def attempt_completion(%TaskOccurrence{} = occurrence, attribution) do
    outcome = if done?(occurrence), do: :duplicate_completion_attempted, else: :completed
    event_type = if outcome == :completed, do: "completed", else: "duplicate_completion_attempted"
    {:ok, event} = record_event(occurrence, event_type, attribution)
    {outcome, event}
  end

  @doc """
  Completes a task from the web UI, attributed to the scope's user. Generates
  the current occurrence if needed, then records a `completed` (or
  `duplicate_completion_attempted`) event with `source: "web"` — the same
  mechanism as a scan, just from the browser. The user must belong to the task's
  household; the matching `household_id` binding enforces that.
  """
  def complete_via_web(
        %Scope{user: %User{id: user_id}, household: %Household{id: household_id}},
        %Task{household_id: household_id} = task
      ) do
    occurrence = current_or_create_occurrence(task)
    {outcome, _event} = attempt_completion(occurrence, %{source: "web", user_id: user_id})
    {:ok, outcome}
  end

  def complete_via_web(_scope, _task), do: {:error, :unauthorized}

  defp record_event(%TaskOccurrence{id: occurrence_id}, event_type, attribution) do
    %TaskEvent{
      task_occurrence_id: occurrence_id,
      user_id: attribution[:user_id],
      nfc_tag_id: attribution[:nfc_tag_id],
      automation_command_id: attribution[:automation_command_id],
      integration_bearer_token_id: attribution[:integration_bearer_token_id]
    }
    |> TaskEvent.changeset(%{
      event_type: event_type,
      source: attribution[:source] || "system",
      occurred_at: DateTime.utc_now()
    })
    |> Repo.insert()
  end

  defp unwrap({:ok, record}), do: record
  defp unwrap({:error, changeset}), do: Repo.rollback(changeset)
end
