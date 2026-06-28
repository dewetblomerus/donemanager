defmodule DoneManager.Tasks do
  @moduledoc """
  Tasks and their occurrences.

  Read/write functions take a `%Scope{}` and only ever touch the scope's
  household, so cross-household access is structurally impossible. Completion
  status is stored on the occurrence (`completed_at`, `completed_by_id`). In the
  current slice a task is created with one eager occurrence; the single-invariant
  reconcile loop comes later. See architecture/stages.md and
  architecture/scheduling.md.
  """

  import Ecto.Query, warn: false

  alias DoneManager.Accounts.Scope
  alias DoneManager.Accounts.User
  alias DoneManager.Households.Household
  alias DoneManager.Households.HouseholdMembership
  alias DoneManager.Repo
  alias DoneManager.Tasks.Task
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
  current occurrence, so the slice has something an execute can complete without
  a scheduler.
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

  @doc """
  Updates a task and ensures it still has one open occurrence (create/update
  upserts the open occurrence; see architecture/scheduling.md). The task must
  already have been loaded through a scope.
  """
  def update_task(%Scope{household: %Household{id: household_id}}, %Task{} = task, attrs) do
    if task.household_id == household_id do
      with {:ok, task} <- task |> Task.changeset(attrs) |> Repo.update() do
        current_or_create_occurrence(task)
        {:ok, task}
      end
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
      limit: 1,
      preload: [:completed_by]
    )
    |> Repo.one()
  end

  @doc """
  The task's current occurrence, generating one if none exists. The eager
  occurrence makes this rare, but an execute must always have something to act
  on, so the path self-heals rather than failing.
  """
  def current_or_create_occurrence(%Task{} = task) do
    case current_occurrence(task) do
      nil -> task |> insert_occurrence() |> unwrap_occurrence()
      occurrence -> occurrence
    end
  end

  @doc """
  Fetches an occurrence by id, but only if the scope's user is a member of its
  task's household, or raises (default-deny). Task and `completed_by` preloaded.
  """
  def get_occurrence!(%Scope{user: %User{id: user_id}}, id) do
    from(o in TaskOccurrence,
      join: t in Task,
      on: t.id == o.task_id,
      join: m in HouseholdMembership,
      on: m.household_id == t.household_id,
      where: o.id == ^id and m.user_id == ^user_id,
      preload: [:completed_by, task: :household]
    )
    |> Repo.one!()
  end

  @doc "Whether an occurrence has been completed."
  def done?(%TaskOccurrence{} = occurrence), do: TaskOccurrence.done?(occurrence)

  @doc """
  Completes an occurrence, attributed to `user_id`. Idempotent: if it was
  already done it is not re-stamped. Returns `{:completed, occurrence}` or
  `{:duplicate, occurrence}`.
  """
  def complete_occurrence(%TaskOccurrence{} = occurrence, user_id) do
    if TaskOccurrence.done?(occurrence) do
      {:duplicate, occurrence}
    else
      occurrence =
        occurrence
        |> TaskOccurrence.changeset(%{
          completed_at: DateTime.utc_now(),
          completed_by_id: user_id
        })
        |> Repo.update()
        |> unwrap()
        |> Repo.preload(:completed_by)

      {:completed, occurrence}
    end
  end

  @doc """
  Completes a task's current occurrence from the web UI, attributed to the
  scope's user — the same mechanism as a tap. The task must already have been
  loaded through a scope (membership-checked). Returns `{:ok, :completed}` or
  `{:ok, :duplicate}`.
  """
  def complete_via_web(
        %Scope{user: %User{id: user_id}, household: %Household{id: household_id}},
        %Task{household_id: household_id} = task
      ) do
    {outcome, _occurrence} =
      task |> current_or_create_occurrence() |> complete_occurrence(user_id)

    {:ok, outcome}
  end

  def complete_via_web(_scope, _task), do: {:error, :unauthorized}

  defp insert_occurrence(%Task{id: task_id}) do
    %TaskOccurrence{task_id: task_id}
    |> TaskOccurrence.changeset(%{due_at: DateTime.utc_now()})
    |> Repo.insert()
  end

  defp unwrap_occurrence({:ok, occurrence}), do: Repo.preload(occurrence, :completed_by)

  defp unwrap({:ok, record}), do: record
  defp unwrap({:error, changeset}), do: Repo.rollback(changeset)
end
