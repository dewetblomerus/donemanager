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
  require Logger

  alias DoneManager.Accounts.Scope
  alias DoneManager.Accounts.User
  alias DoneManager.Households.Household
  alias DoneManager.Households.HouseholdMembership
  alias DoneManager.Links.Link
  alias DoneManager.Links.LinkTask
  alias DoneManager.Repo
  alias DoneManager.Tasks
  alias DoneManager.Tasks.Task
  alias DoneManager.Tasks.TaskOccurrence

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

  @doc """
  Claims a never-seen UUIDv7 tag URL for the signed-in user's only household.

  This supports pre-written NFC tags. The ID must be a valid UUIDv7, must not
  already exist anywhere, and the user must belong to exactly one household.
  `Repo.one/1` intentionally raises if the user has multiple households.
  """
  def claim_new_link_for_only_household(%Scope{user: %User{id: user_id}} = scope, id) do
    with true <- uuidv7?(id),
         nil <- Repo.get(Link, id),
         %Household{} = household <- only_household_for_user!(user_id) do
      scope
      |> Scope.put_household(household)
      |> create_link_with_id(id)
    else
      false -> {:error, :invalid_id}
      %Link{} -> {:error, :not_unique}
      nil -> {:error, :no_household}
      {:error, _reason} = error -> error
    end
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
    with true <- link.household_id == household_id,
         %Task{} <- Repo.get_by(Task, id: task_id, household_id: household_id) do
      case Repo.get_by(LinkTask, link_id: link.id, task_id: task_id) do
        %LinkTask{} = binding ->
          {:ok, binding}

        nil ->
          %LinkTask{household_id: household_id, link_id: link.id}
          |> LinkTask.changeset(%{task_id: task_id})
          |> Repo.insert()
      end
    else
      false -> {:error, :unauthorized}
      nil -> {:error, :not_found}
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
  occurrence. Timer occurrences are generated on demand by the tap; scheduled and
  interval occurrences are owned by the reconcile loop and never created here.

  Returns `{:ok, occurrence}`, `{:warning, context}` for a link with tasks but
  no task actionable in the current execute window, `{:error, :not_found}` (no
  such link, or the user is not a member of its household), `{:error, :unassigned}`
  (the link drives no active task), or `{:error, :no_occurrence}` (the link's
  tasks have no current occurrence at all — an anomaly the reconcile loop should
  prevent; logged loudly, soft in the UI rather than silently generating one).
  """
  def resolve_execute(%Scope{user: %User{id: user_id}}, link_id, now \\ DateTime.utc_now()) do
    case fetch_link_for_member(link_id, user_id) do
      nil -> {:error, :not_found}
      link -> resolve_actionable(link, now)
    end
  end

  @doc """
  Resolves the read-only status page for a link. This uses the same membership
  authorization and task set as execute resolution, but never returns an
  executable occurrence and never mutates task state.
  """
  def resolve_status(%Scope{user: %User{id: user_id}}, link_id, now \\ DateTime.utc_now()) do
    case fetch_link_for_member(link_id, user_id) do
      nil ->
        {:error, :not_found}

      link ->
        local_time = local_time(now, link.household.timezone)

        link
        |> actionable_tasks()
        |> tasks_with_occurrences()
        |> status_context(local_time)
    end
  end

  defp fetch_link_for_member(link_id, user_id) do
    if uuidv7?(link_id) do
      fetch_uuidv7_link_for_member(link_id, user_id)
    end
  end

  defp fetch_uuidv7_link_for_member(link_id, user_id) do
    from(l in Link,
      join: m in HouseholdMembership,
      on: m.household_id == l.household_id,
      where: l.id == ^link_id and l.active and m.user_id == ^user_id,
      preload: [:household]
    )
    |> Repo.one()
  end

  defp create_link_with_id(%Scope{household: %Household{id: household_id}}, id) do
    %Link{id: id, household_id: household_id}
    |> Link.changeset(%{})
    |> Repo.insert()
  end

  defp only_household_for_user!(user_id) do
    from(h in Household,
      join: m in HouseholdMembership,
      on: m.household_id == h.id,
      where: m.user_id == ^user_id
    )
    |> Repo.one()
  end

  defp uuidv7?(id) when is_binary(id) do
    Regex.match?(
      ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i,
      id
    )
  end

  defp uuidv7?(_id), do: false

  defp resolve_actionable(%Link{} = link, now) do
    timezone = link.household.timezone
    local_time = local_time(now, timezone)
    pairs = tasks_with_occurrences(actionable_tasks(link))

    in_window =
      Enum.filter(pairs, fn {task, occ} ->
        occ && execute_window_contains?(task, local_time)
      end)

    case select_started_pair(in_window, now, timezone) do
      {_task, occurrence} -> {:ok, occurrence}
      nil -> unactionable_result(pairs, local_time)
    end
  end

  # Pairs each task with its current occurrence. For scheduled/interval tasks a
  # missing occurrence is an anomaly — task creation seeds one and the reconcile
  # loop keeps one open — so it is logged loudly rather than silently find-or-
  # created, keeping a generation gap visible instead of papered over (see
  # architecture/scheduling.md). Timers are exempt: they are generated on demand
  # by the tap itself, so they legitimately create here (including a fresh one
  # once the prior countdown is done).
  defp tasks_with_occurrences(tasks) do
    Enum.map(tasks, fn task -> {task, occurrence_for(task)} end)
  end

  defp occurrence_for(%Task{task_type: "timer"} = task),
    do: Tasks.current_or_create_occurrence(task)

  defp occurrence_for(%Task{} = task) do
    occurrence = Tasks.current_occurrence(task)
    if is_nil(occurrence), do: log_missing_occurrence(task)
    occurrence
  end

  defp log_missing_occurrence(%Task{id: id, name: name}) do
    Logger.error(
      "execute: task #{id} (#{inspect(name)}) has no current occurrence; " <>
        "the reconcile loop should keep one open"
    )
  end

  defp actionable_tasks(%Link{id: link_id}) do
    from(lt in LinkTask,
      join: t in Task,
      on: t.id == lt.task_id,
      where: lt.link_id == ^link_id and t.active,
      select: t
    )
    |> Repo.all()
  end

  # Among the in-window pairs, prefer ones with an open occurrence, then the
  # earliest due — deterministic routing for a multi-task link. A task's current
  # occurrence may belong to a *future* day (once tonight's resolves, the loop
  # opens tomorrow's), so drop any whose window has not started yet: without this
  # a second tap inside tonight's window would complete tomorrow's occurrence.
  defp select_started_pair([], _now, _timezone), do: nil

  defp select_started_pair(pairs, now, timezone) do
    pairs
    |> Enum.filter(fn {task, occ} -> occurrence_started?(task, occ, now, timezone) end)
    |> case do
      [] ->
        nil

      started ->
        open = Enum.reject(started, fn {_task, occ} -> Tasks.done?(occ) end)

        ((open == [] && started) || open)
        |> Enum.sort_by(fn {_task, occ} -> occ.due_at end, DateTime)
        |> List.first()
    end
  end

  # A scheduled occurrence is actionable only from when its window opens — the
  # `valid_from` (or start of day) on the occurrence's own due date. Interval and
  # timer occurrences have no dated window and stay tappable until done.
  defp occurrence_started?(%Task{task_type: "scheduled"} = task, occurrence, now, timezone),
    do: DateTime.compare(now, window_start_instant(task, occurrence, timezone)) != :lt

  defp occurrence_started?(_task, _occurrence, _now, _timezone), do: true

  defp window_start_instant(
         %Task{valid_from: valid_from},
         %TaskOccurrence{due_at: due_at},
         timezone
       ) do
    due_date = due_at |> to_local(timezone) |> DateTime.to_date()
    local_instant(due_date, valid_from || ~T[00:00:00], timezone)
  end

  defp to_local(%DateTime{} = utc, timezone) do
    case DateTime.shift_zone(utc, timezone) do
      {:ok, local} -> local
      {:error, _} -> utc
    end
  end

  defp local_instant(date, time, timezone) do
    case DateTime.new(date, time, timezone) do
      {:ok, dt} -> DateTime.shift_zone!(dt, "Etc/UTC")
      {:ambiguous, first, _second} -> DateTime.shift_zone!(first, "Etc/UTC")
      {:gap, _before, just_after} -> DateTime.shift_zone!(just_after, "Etc/UTC")
      {:error, _} -> DateTime.new!(date, time, "Etc/UTC")
    end
  end

  # The execute path fell through to no actionable occurrence: reuse the status
  # context, but as a `:warning` (nothing was executed) rather than `:ok`.
  defp unactionable_result(pairs, local_time) do
    case status_context(pairs, local_time) do
      {:ok, context} -> {:warning, context}
      other -> other
    end
  end

  defp status_context([], _local_time), do: {:error, :unassigned}

  defp status_context(pairs, local_time) do
    case Enum.filter(pairs, fn {_task, occ} -> occ end) do
      [] ->
        {:error, :no_occurrence}

      present ->
        {:ok,
         %{
           outside_execution_hours:
             Enum.all?(pairs, fn {task, _occ} ->
               not execute_window_contains?(task, local_time)
             end),
           previous: nearest_previous_occurrence(present, local_time),
           next: nearest_next_occurrence(present, local_time)
         }}
    end
  end

  defp nearest_previous_occurrence(tasks_with_occurrences, local_time) do
    tasks_with_occurrences
    |> Enum.min_by(fn {task, _occurrence} ->
      seconds_since_window_end(task, local_time)
    end)
    |> occurrence_from_pair()
  end

  defp nearest_next_occurrence(tasks_with_occurrences, local_time) do
    tasks_with_occurrences
    |> Enum.min_by(fn {task, _occurrence} ->
      seconds_until_window_start(task, local_time)
    end)
    |> occurrence_from_pair()
  end

  defp occurrence_from_pair({_task, %TaskOccurrence{} = occurrence}),
    do: Repo.preload(occurrence, [:completed_by, task: :household])

  defp local_time(%DateTime{} = utc, timezone) do
    case DateTime.shift_zone(utc, timezone) do
      {:ok, local} -> DateTime.to_time(local)
      {:error, _} -> DateTime.to_time(utc)
    end
  end

  # The execute window is [valid_from, expiration_time): start-inclusive,
  # end-exclusive, crossing midnight when expiration is at or before valid_from.
  # A null bound is open on that side (null valid_from = from start of day; null
  # expiration = no end, e.g. interval tasks tappable until done).
  defp execute_window_contains?(%Task{valid_from: nil, expiration_time: nil}, _time), do: true

  defp execute_window_contains?(%Task{valid_from: nil, expiration_time: until_time}, time),
    do: Time.compare(time, until_time) == :lt

  defp execute_window_contains?(%Task{valid_from: from_time, expiration_time: nil}, time),
    do: Time.compare(time, from_time) in [:eq, :gt]

  defp execute_window_contains?(
         %Task{valid_from: from_time, expiration_time: until_time},
         time
       ) do
    if Time.compare(from_time, until_time) == :lt do
      Time.compare(time, from_time) in [:eq, :gt] and Time.compare(time, until_time) == :lt
    else
      Time.compare(time, from_time) in [:eq, :gt] or Time.compare(time, until_time) == :lt
    end
  end

  defp seconds_since_window_end(%Task{expiration_time: until_time}, time) do
    if until_time do
      positive_time_diff(time, until_time)
    else
      0
    end
  end

  defp seconds_until_window_start(%Task{valid_from: from_time}, time) do
    if from_time do
      positive_time_diff(from_time, time)
    else
      0
    end
  end

  defp positive_time_diff(later, earlier) do
    seconds = Time.diff(later, earlier, :second)

    if seconds >= 0 do
      seconds
    else
      seconds + 24 * 60 * 60
    end
  end
end
