# Scheduling

How occurrences are generated and reminders are sent. Generation (the reconcile
loop) and the **Remind** step are both implemented now, driven by the one-minute
`TaskReconcileWorker` Oban cron — generation first, then reminders, each tick.
Task creation still also eagerly creates the first occurrence.

## The single invariant

The planned `scheduled` and `interval` generation model shares one rule:

> **A task has exactly one open occurrence. When it resolves, create the next.**

An occurrence is **resolved** when `completed_at` is set **or** `expires_at < now`. Completion is stored; expiry is derived from `expires_at`, so there is no status column. This invariant is the whole planned generation model — there is no rolling-horizon pre-generation, and future occurrences are computed for display only, never stored.

The constraint that a `scheduled` task must set `expiration_time` exists to keep this invariant from stalling: a missed slot resolves *by expiring*, so the next slot is created even when nobody did the task. `interval` tasks have `expires_at = null` and resolve only on completion, so they stay open and grow more overdue until done.

## The reconcile loop

One Oban cron job will run every minute and derive all work from DB state — it will not process a delta. Each run, for each active `scheduled`/`interval` task:

1. **Generate.** Find the task's latest occurrence. If it is resolved (`completed_at` set or `expires_at < now`) and no later occurrence exists yet, create the next one. Bootstrap (a brand-new task with no occurrences) is the same path. The only per-type difference is the next `due_at`:
   - `scheduled` — the next wall-clock `due_time` slot honoring `cadence_weekdays` (empty = every day), in `households.timezone`: today if `due_time` is still ahead of now *and* today is an allowed weekday, otherwise the next allowed weekday at `due_time`. `expires_at` is then derived from `expiration_time` by the midnight-crossing rule in [database.md](database.md). Task creation already does this — the first occurrence is a correct future slot, not `due_at = now`. What the loop adds is generating the *next* slot once the current one resolves.
   - `interval` — the resolved occurrence's `completed_at` plus `interval_minutes`, with `expires_at = null`.
2. **Remind.** For each open, overdue occurrence (across **all** task types) and each recipient — household members with a `users.pushover_user_key` — send a reminder when there is no prior reminder, or `now - last_sent_at >= tasks.reminder_interval_minutes` (a null interval means a single reminder). The send is gated and recorded by the one `notification_deliveries` row for `(occurrence, user, "reminder")`, which is **upserted in place** (bumping `reminder_count`, stamping `last_sent_at`/`last_status`) — see [database.md](database.md). Quiet hours soften delivery rather than skipping it: a recipient in their quiet-hours window (per-user `quiet_hours_*`, in `households.timezone`) gets the push at Pushover priority `-1` (silent), normal priority otherwise.

`timer` occurrences are not *generated* by the loop — they are created/cancelled on demand. But the Remind step scans every task type, so a timer past its `due_at` is reminded like any other open, overdue occurrence. That is what makes timer tasks actionable.

## One function, three triggers

Generating an occurrence should become the same operation — "ensure this task has a correct open occurrence" — whether it runs from the loop, from task creation, or from a task edit. **Creating or updating a task should upsert its single open occurrence**: insert it if missing, recompute `due_at`/`expires_at` if it exists, and **never touch resolved (completed/expired) occurrences** so history stays honest. So an edit to `due_time`/cadence/`expiration_time` (or `interval_minutes`) is immediately reflected in the open occurrence, and the loop and the editor share one code path. The `(task_id, due_at)` uniqueness guard keeps an edit and a concurrent loop tick from inserting twice.

**Outstanding:** task *creation* computes the correct slot via `TaskOccurrence.schedule_attrs/3`, but `update_task` does **not** yet recompute the open occurrence — `current_or_create_occurrence` only creates one when none exists. Editing a task's `due_time`/cadence/`expiration_time` currently leaves the existing open occurrence's `due_at`/`expires_at` stale. Closing this means routing `update_task` through the same `schedule_attrs/3` upsert (skipping resolved occurrences).

## Display status in the web UI

The task list and task show page derive a **display status** that tracks the household-local clock, not just the newest occurrence. This reuses the status the tag status page already computes (`Links.resolve_status` → `outside_execution_hours`, `previous`, `next`; see [database.md](database.md)) so a scanned tag and the web UI agree.

The status is derived for the **current local day**, picking the occurrence that day's run is about rather than the literal newest row:

- **Not yet** — `now` is before the occurrence's window opens (`valid_from`).
- **Open / Overdue** — inside the window, not completed (overdue once past `due_time`; `interval` tasks grow overdue with no window).
- **Done** — completed; held for the rest of the local day (see the boundary decision in [flows.md](flows.md)).
- **Missed** — `scheduled` window closed (`expires_at < now`) with no completion.

At local midnight the day resets to the next occurrence, so nothing reads "Done" from a prior day. The task show page may still display the previous completion as history, but its headline status is today's state.

**This is the bug to fix.** Today `TaskLive.Index` and `TaskLive.Show` read `Tasks.current_occurrence/1` (newest by `inserted_at`) and label it `done?`/`open` only. That shows a bare "Done" for an occurrence completed yesterday, and it has no "Not yet"/"Overdue"/"Missed" states. The fix is a time-aware status derivation shared by both views (and ideally the same code the status page uses), keyed on the household timezone.

A related generation edge case: completing a `scheduled` task *before* its `due_time` makes `next_due_date` recompute the same slot, which collides on the `(task_id, due_at)` guard and does not advance until `due_time` passes — leaving the completed occurrence as the "current" one in the meantime. Worth fixing alongside, but the display derivation above is the primary correction.

## Missing occurrence at execute

Once task creation makes the first scheduled occurrence correctly and the loop keeps one open, an execute should always find one. The two cases:

- **Current occurrence already resolved** (the normal idempotent tap-twice): redirect to it and show "done". Not an error.
- **No occurrence at all**: anomalous. For now, fail **loud in the logs, soft in the UI** — render a clear "no active occurrence" page and log an error to investigate, rather than silently find-or-creating (which would hide a generation bug while the system is still being proven out). Find-or-create can be added later if a real timing gap ever appears.

State lives in Postgres (`task_occurrences` and `notification_deliveries`), not in the scheduler. A crash, restart, or skipped tick self-heals on the next run because work is recomputed from current state.

## Idempotency

Generation idempotency is structural: the loop creates the next occurrence only when the current one is resolved and no later one exists, so a re-run finds the open occurrence already present and does nothing. Back it with a uniqueness guard on `(task_id, due_at)` so two overlapping runs can't insert the same next occurrence twice.

Reminder idempotency comes from the `notification_deliveries` row, not the queue: each reminder reads the `(occurrence, user, "reminder")` row's `last_sent_at`, so a re-run within the interval sees "already sent" and skips. Because the row is upserted (one per occurrence+recipient+type), a re-run never accumulates duplicates. This is the role the dropped `task_events` table used to play.

## Why Oban

Oban gives single concurrent execution (`FOR UPDATE SKIP LOCKED`; cron inserts one job per minute boundary via a unique index) plus **at-least-once** completion. Effectively-once comes from the idempotent reconciliation above, not the queue — Oban only guarantees the loop fires.

The reconcile worker is `unique` over non-terminal states so an overrunning run causes the next tick to be skipped rather than piling up:

```elixir
use Oban.Worker,
  queue: :scheduler,
  unique: [period: :infinity, states: [:available, :scheduled, :executing, :retryable]]
```

Paired with a single-slot queue (`queues: [scheduler: 1]`). Skipping a tick is safe: because the loop reconciles from DB state, the next run catches everything the skipped one would have.

## Open question: brand-new interval bootstrap

When a new `interval` task's *first* occurrence is due — `due_at = created_at + interval_minutes`, or due immediately — is undecided. Minor; settle when generation is built.
