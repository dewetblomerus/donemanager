# Scheduling

How occurrences are generated and reminders are sent.

## Model: a periodic reconcile loop

One Oban cron job runs every minute and derives all work from DB state — it does not process a delta. Each run:

1. **Generate occurrences** for `scheduled` tasks across a rolling horizon (e.g. today and tomorrow), skipping any that already exist.
2. **Send reminders**: for each occurrence that is due/overdue and not completed, and for each notify recipient, send a reminder when `now - last reminder_sent >= reminder_interval_minutes`. The Pushover sender reads the recipient's quiet hours and sets message priority (silent during quiet hours). Record a `reminder_sent` `task_event` and a `notification_deliveries` row. Exact quiet-hours behavior for reminders is an open question (see [decisions.md](decisions.md)).

State lives in Postgres (`task_events`, `notification_deliveries`), not in the scheduler. A crash, restart, or skipped tick self-heals on the next run because work is recomputed from current state.

## What each task_type contributes

- `scheduled` — the only type the periodic generator creates occurrences for, from its wall-clock cadence.
- `interval` — occurrences are not generated on a tick. The next one is rolled forward at *completion* (`due_at = last completed event + cadence_interval_minutes`). The loop only sends its reminders.
- `timer` — occurrences are created on scan by the derived `toggle_timer` behaviour (`due_at = now + tasks.timer_minutes`). The loop only sends its reminders.

## Exactly-once

Oban gives single concurrent execution (`FOR UPDATE SKIP LOCKED`; cron inserts one job per minute boundary via a unique index) plus **at-least-once** completion. A crash after sending but before the job is marked complete causes a retry, so a reminder can be re-attempted.

Effectively-once comes from idempotency, not the queue: each reminder is gated on the recorded `reminder_sent` event, so a re-run sees "already sent within the interval" and skips. The DB check does the de-dup; Oban only guarantees the loop fires.

## Overlap and skip

The reconcile worker is `unique` over non-terminal states so an overrunning run causes the next tick to be skipped rather than piling up:

```elixir
use Oban.Worker,
  queue: :scheduler,
  unique: [period: :infinity, states: [:available, :scheduled, :executing, :retryable]]
```

Paired with a single-slot queue (`queues: [scheduler: 1]`) so a queued job can't run alongside a running one. Skipping a tick is safe: because the loop reconciles from DB state, the next run catches everything the skipped one would have.
