defmodule DoneManager.Links do
  @moduledoc """
  Links — the public, stable deep-link targets written onto NFC tags / QR codes
  — and the bindings that drive tasks from them.

  Web functions take a `%Scope{}` and only touch the scope's household. The
  execute path (`GET /links/:id`) is keyed on the requesting user's household
  membership instead of the current household, so a tag resolves the right
  household regardless of which one is currently selected, and a non-member is
  refused. See architecture/database.md.
  """

  import Ecto.Query, warn: false

  alias DoneManager.Accounts.Scope
  alias DoneManager.Accounts.User
  alias DoneManager.Households.Household
  alias DoneManager.Households.HouseholdMembership
  alias DoneManager.Links.Link
  alias DoneManager.Links.LinkTask
  alias DoneManager.Repo
  alias DoneManager.Tasks
  alias DoneManager.Tasks.Task

  ## Links (web, scope-keyed)

  @doc "Links in the scope's current household, newest first."
  def list_links(%Scope{household: %Household{id: household_id}}) do
    from(l in Link, where: l.household_id == ^household_id, order_by: [desc: l.inserted_at])
    |> Repo.all()
  end

  @doc """
  Links in the scope's household, newest first, each with its bound tasks
  preloaded so the UI can show what every link drives.
  """
  def list_links_with_tasks(%Scope{household: %Household{id: household_id}}) do
    bindings = from(lt in LinkTask, order_by: [asc: lt.inserted_at], preload: [:task])

    from(l in Link,
      where: l.household_id == ^household_id,
      order_by: [desc: l.inserted_at],
      preload: [link_tasks: ^bindings]
    )
    |> Repo.all()
  end

  @doc "Fetches a link in the scope's current household, or raises (default-deny)."
  def get_link!(%Scope{household: %Household{id: household_id}}, id) do
    Repo.get_by!(Link, id: id, household_id: household_id)
  end

  @doc "Creates a link in the scope's current household."
  def create_link(%Scope{household: %Household{id: household_id}}, attrs \\ %{}) do
    %Link{household_id: household_id}
    |> Link.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates a link (its label/active) in the scope's household."
  def update_link(%Scope{household: %Household{id: household_id}}, %Link{} = link, attrs) do
    if link.household_id == household_id do
      link |> Link.changeset(attrs) |> Repo.update()
    else
      {:error, :unauthorized}
    end
  end

  @doc "Hard-deletes a link in the scope's household; its bindings cascade away."
  def delete_link(%Scope{household: %Household{id: household_id}}, %Link{} = link) do
    if link.household_id == household_id do
      Repo.delete(link)
    else
      {:error, :unauthorized}
    end
  end

  def change_link(%Link{} = link \\ %Link{}, attrs \\ %{}), do: Link.changeset(link, attrs)

  ## Bindings (web, scope-keyed)

  @doc "Binds a task to a link. Idempotent on `(link_id, task_id)`."
  def bind_task(%Scope{household: %Household{id: household_id}}, %Link{} = link, task_id) do
    if link.household_id == household_id do
      %LinkTask{household_id: household_id, link_id: link.id}
      |> LinkTask.changeset(%{task_id: task_id})
      |> Repo.insert()
    else
      {:error, :unauthorized}
    end
  end

  @doc "Removes a binding by id in the scope's household."
  def unbind_task(%Scope{household: %Household{id: household_id}}, link_task_id) do
    case Repo.get_by(LinkTask, id: link_task_id, household_id: household_id) do
      nil -> {:error, :not_found}
      %LinkTask{} = binding -> Repo.delete(binding)
    end
  end

  @doc "Tasks already bound to a link."
  def list_tasks_for_link(%Link{id: link_id}) do
    from(lt in LinkTask,
      where: lt.link_id == ^link_id,
      order_by: [asc: lt.inserted_at],
      preload: [:task]
    )
    |> Repo.all()
    |> Enum.map(& &1.task)
  end

  ## Execute resolution (membership-keyed)

  @doc """
  Resolves a tap of `GET /links/:id` to the task occurrence that should be
  acted on. Authorizes the user by household membership, picks the actionable
  task among the link's bindings by execute window, and returns its current
  occurrence (generating one if needed).

  Returns `{:ok, occurrence}`, `{:error, :not_found}` (no such link, or the user
  is not a member of its household), or `{:error, :unassigned}` (the link drives
  no task actionable right now).
  """
  def resolve_execute(%Scope{user: %User{id: user_id}}, link_id, now \\ DateTime.utc_now()) do
    case fetch_link_for_member(link_id, user_id) do
      nil -> {:error, :not_found}
      link -> resolve_actionable(link, now)
    end
  end

  defp fetch_link_for_member(link_id, user_id) do
    from(l in Link,
      join: m in HouseholdMembership,
      on: m.household_id == l.household_id,
      where: l.id == ^link_id and l.active and m.user_id == ^user_id,
      preload: [:household]
    )
    |> Repo.one()
  end

  defp resolve_actionable(%Link{} = link, now) do
    local_time = local_time(now, link.household.timezone)

    actionable_tasks(link)
    |> Enum.filter(&execute_window_contains?(&1, local_time))
    |> select_task_by_occurrence()
    |> case do
      nil -> {:error, :unassigned}
      task -> {:ok, Tasks.current_or_create_occurrence(task)}
    end
  end

  # Timer tasks (toggle_timer) are deferred, so only completable types resolve.
  defp actionable_tasks(%Link{id: link_id}) do
    from(lt in LinkTask,
      join: t in Task,
      on: t.id == lt.task_id,
      where: lt.link_id == ^link_id and t.active and t.task_type in ["scheduled", "interval"],
      select: t
    )
    |> Repo.all()
  end

  # Among the windowed tasks, prefer ones with an open occurrence, then the
  # earliest due — deterministic routing for a multi-task link.
  defp select_task_by_occurrence([]), do: nil

  defp select_task_by_occurrence(tasks) do
    pairs = Enum.map(tasks, fn task -> {task, Tasks.current_or_create_occurrence(task)} end)

    open = Enum.reject(pairs, fn {_task, occ} -> Tasks.done?(occ) end)

    ((open == [] && pairs) || open)
    |> Enum.sort_by(fn {_task, occ} -> occ.due_at end, DateTime)
    |> List.first()
    |> elem(0)
  end

  defp local_time(%DateTime{} = utc, timezone) do
    case DateTime.shift_zone(utc, timezone) do
      {:ok, local} -> DateTime.to_time(local)
      {:error, _} -> DateTime.to_time(utc)
    end
  end

  defp execute_window_contains?(
         %Task{execute_window_start_time: nil, execute_window_end_time: nil},
         _time
       ),
       do: true

  defp execute_window_contains?(
         %Task{execute_window_start_time: from_time, execute_window_end_time: until_time},
         time
       ) do
    if Time.compare(from_time, until_time) == :lt do
      Time.compare(time, from_time) in [:eq, :gt] and Time.compare(time, until_time) == :lt
    else
      Time.compare(time, from_time) in [:eq, :gt] or Time.compare(time, until_time) == :lt
    end
  end
end
