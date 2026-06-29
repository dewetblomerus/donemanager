# Database

This is the current implemented database shape for Done Manager. Planned notification
tables and scheduling behavior are described after the current schema.

## Entity Relationship Diagram

```mermaid
erDiagram
    households ||--o{ household_memberships : has
    users ||--o{ household_memberships : joins
    households ||--o{ household_invitations : sends
    users ||--o{ household_invitations : invites
    households ||--o{ tasks : owns
    households ||--o{ links : owns
    households ||--o{ link_tasks : owns
    tasks ||--o{ link_tasks : receives
    links ||--o{ link_tasks : invokes
    tasks ||--o{ task_occurrences : schedules
    users ||--o{ task_occurrences : completes

    households {
        uuid id PK
        string name
        string timezone
        datetime inserted_at
        datetime updated_at
    }

    users {
        uuid id PK
        string auth0_sub UK
        string email UK
        string display_name
        time quiet_hours_start
        time quiet_hours_end
        datetime inserted_at
        datetime updated_at
    }

    household_memberships {
        uuid id PK
        uuid household_id FK
        uuid user_id FK
        string role
        datetime inserted_at
        datetime updated_at
    }

    household_invitations {
        uuid id PK
        uuid household_id FK
        uuid inviter_id FK
        string invitee_email
        string status
        datetime expires_at
        datetime inserted_at
        datetime updated_at
    }

    tasks {
        uuid id PK
        uuid household_id FK
        string name
        string description
        string task_type
        string[] cadence_weekdays
        integer interval_minutes
        time due_time
        time expiration_time
        time valid_from
        integer reminder_interval_minutes
        boolean active
        datetime inserted_at
        datetime updated_at
    }

    task_occurrences {
        uuid id PK
        uuid task_id FK
        uuid completed_by_id FK
        datetime due_at
        datetime expires_at
        datetime completed_at
        datetime inserted_at
        datetime updated_at
    }

    links {
        uuid id PK
        uuid household_id FK
        string label
        boolean active
        datetime inserted_at
        datetime updated_at
    }

    link_tasks {
        uuid id PK
        uuid household_id FK
        uuid task_id FK
        uuid link_id FK
        datetime inserted_at
        datetime updated_at
    }

```

## Authentication Model

Everyone authenticates through Auth0. The `users.auth0_sub` field stores the stable Auth0 subject and maps the external identity to the app user. There is no secret on the tag and no integration token in V1: a tag carries only a public URL (the link execute URL below), and acting on it requires a logged-in user who is a verified member of the link's household. Authorization comes from `household_memberships`, attribution from the session user. A future API integration (Home Assistant, Arduino) can reintroduce a bearer-token table when there is a real non-browser client; V1 has no such client and so no token table.

Notifications are implemented for reminders. Each user owns a single encrypted `users.pushover_user_key` (a user belongs to multiple households and carries the same key with them). Reminders fan out to all members of a task's household who have a key set. Households eventually curating *which* members are notified is still future work. See [scheduling.md](scheduling.md) for the send path and `notification_deliveries` below.

## Notes

- Primary keys should use UUIDv7.
- Every `datetime` column above is a UTC instant stored as Ecto `utc_datetime_usec` (`timestamptz`). The `time` columns (`due_time`, `expiration_time`, `valid_from`, `quiet_hours_start/end`) are wall-clock times of day, not instants, interpreted in `households.timezone`. See [decisions.md](decisions.md).
- `households` is included even if V1 only has one household. It keeps ownership explicit without adding much complexity.
- `households.timezone` is the single timezone for household-local routines.
- `users.quiet_hours_start` and `quiet_hours_end` are per-user times (interpreted in the household timezone). They are per-user from V1 because household members keep different sleeping hours. They shape *how* a notification is delivered, not a hard on/off: the future Pushover sender reads the recipient's quiet hours and picks message priority. Notifications are planned; the columns are kept because they are cheap and the shape does not change with the answer.
- `household_memberships.role` can start simple, such as `owner` or `member`.
- `household_invitations` holds invites to an `invitee_email` that may not have a `users` row yet, so it is separate from `household_memberships`. `inviter_id` references the inviting user. `status` tracks the lifecycle (such as `pending`, `accepted`, `expired`). `expires_at` bounds how long an invite is valid. On acceptance after the invitee signs up, a `household_memberships` row is created and the invitation is marked accepted. No email is sent in V1; the invitee learns of the invite in-app after signing up.
- Notifications use a single encrypted `users.pushover_user_key` per user. A `pushover_destinations` table (multiple labelled devices per user) was considered and deferred — see [decisions.md](decisions.md). If other notification integrations are added later, they can get their own tables.
- `tasks` stores the task definition, behavior type, and cadence, such as `Spot breakfast` due daily by 11:00 in the household's timezone.
- `task_type` selects the intended task behavior. Current implemented values: `scheduled`, `interval`, and `timer`. The current slice eagerly creates one occurrence when a task is created; the planned Oban reconcile loop will own recurring generation (see [scheduling.md](scheduling.md)). Each type owns its own columns: `scheduled` uses `cadence_weekdays`, `due_time`, and a required `expiration_time`; `interval` and `timer` both use `interval_minutes`.
- Planned occurrence lifecycle for `scheduled` and `interval`: **a task has exactly one open occurrence; when it resolves, the loop creates the next.** An occurrence is *resolved* when `completed_at` is set **or** `expires_at < now` — completion is stored, expiry is derived. `scheduled` occurrences should have an `expires_at` (their slot resolves even if missed, so the next slot is created), while `interval` has `expires_at = null` and resolves only on completion. Task creation already computes a correct first `scheduled` slot (`due_at`/`expires_at` in `households.timezone`); what remains for the loop is generating the *next* one when the current resolves.
- Enum-like string columns (`task_type`, `status`, `role`, cadence values) are stored lowercase snake_case for schema-wide consistency. The cadence columns take *structural* inspiration from the iCalendar RRULE subset so the schema can grow without repainting — not its literal token casing. If real iCal is ever emitted or parsed, casing is applied at that boundary.
- For `scheduled` tasks, cadence is represented by `cadence_weekdays`. Empty means every day. A non-empty list restricts the task to those weekdays, using lowercase iCalendar-style weekday tokens `mo`, `tu`, `we`, `th`, `fr`, `sa`, `su`. There is no "no days" state; disable or delete a task that should not fire.
- A task has a single `due_time` — one slot per cadence period. **A chore that happens several times a day is modelled as several tasks**, e.g. "Dog breakfast" and "Dog dinner", not one task with two times. This is deliberate: each occurrence then carries task-specific wording so a person knows at a glance whether *this* meal happened, and it composes with multi-task links — one tag by the food bowl drives both tasks, and each task's `[valid_from, expiration_time)` routes a 7am tap to breakfast and a 6pm tap to dinner.
- `interval` (floating) tasks are due relative to their last completion, not a calendar slot, so `expires_at` is null (they never expire). `interval_minutes` is the gap, e.g. `180` for a 3-hour "let the dog out" task or `2880` for a 48-hour "empty the robot mop" task. The next occurrence's `due_at` is the completed occurrence's `completed_at` plus the interval; completing at any time resolves the current occurrence and the loop creates the next, so doing it early pushes the next due-time out. There is no per-date duplicate state — one open occurrence at a time, and the completed chain is a clean history of how often the task was actually done.
- `tasks.reminder_interval_minutes` (nullable) controls re-notification of an overdue occurrence. The backend sends reminders at this cadence until the occurrence is completed, gated on the `notification_deliveries` row's `last_sent_at` for the occurrence+recipient. Null means a single reminder.
- `tasks.due_time` and `tasks.expiration_time` are `Time` values — household-local times of day, not instants. **A `scheduled` (calendar-anchored) task must set `expiration_time`** — a missed slot has to resolve by expiring so it doesn't block the next slot from being created (a forgotten breakfast must not suppress dinner). The column stays nullable at the DB level because `interval`/`timer` tasks never expire and leave it null; the requirement is a changeset validation gated on `task_type = scheduled`. We could not think of a calendar-anchored task that should stay open indefinitely, so this is a deliberate constraint — easy to loosen later, hard to add.
- `task_occurrences` stores each concrete expected instance, such as `Spot breakfast for 2026-06-25`. `due_at` is when the task is due, and nullable `expires_at` is the concrete cutoff after which the occurrence resolves. Both are UTC instants (`utc_datetime_usec`). Task creation computes them for `scheduled` tasks from the wall-clock `due_time`/`expiration_time` in `households.timezone` (the next due slot; see [scheduling.md](scheduling.md)). `interval`/`timer` occurrences are due now with `expires_at = null`. The planned reconcile loop reuses the same computation to generate each subsequent occurrence.
- There is no `occurrence_date` column. The household-local calendar date an occurrence belongs to is derived from `due_at` in `households.timezone` when displaying or grouping — it was only ever needed as a generation key, and the single-invariant model keys on resolution instead. Generation idempotency comes from "create the next only when the current is resolved," backed by a uniqueness guard on `(task_id, due_at)` (see [scheduling.md](scheduling.md)).
- When generating a recurring occurrence, if `expiration_time` is later than `due_time`, `expires_at` is on the same local date as `due_at`. If `expiration_time` is less than or equal to `due_time`, `expires_at` is on the next local date. For example, a task due at 22:00 with `expiration_time` 02:00 expires at 02:00 the next day.
- `task_occurrences` stores completion status directly: `completed_at` (UTC instant) and `completed_by_id` (the household member who executed it, via link or web UI). This reverses the earlier "status is derived, never stored" rule, which depended on `task_events`; that table is dropped in the link redesign (see [decisions.md](decisions.md)). Idempotency lives here — a second execute of an already-completed occurrence is a no-op.
- `links` represents a stable, public deep-link target owned by a household — a physical NFC tag today, a printed QR code or a bookmark tomorrow. It carries no secret. The link's own UUIDv7 PK is the id baked into the tag URL (`…/links/{id}`): the web UI mints the row, hands you the URL to write onto the tag, and the id stays fixed so the physical tag never has to be rewritten. No separate `external_id` is needed — the old design only had one because the tag writer generated the id before the backend saw it. `label` is the human name; `active` allows retiring a link.
- **The link URL is the one stable contract in the app — it is written onto physical tags and is painful to change. Do not rename or restructure `GET /links/{id}`.** Everything else is a web route, free to change. The id is not a secret (it's printed on a public tag); it is a deep-link target. The host (e.g. `app.donemanager.com`) becomes the permanent dependency — it must resolve for as long as any tag is in use. No version prefix is needed: the route is a server-controlled redirect, so old tags can always be re-pointed to a new scheme without rewriting them.
- Tapping a tag opens `GET /links/{id}`, which resolves and redirects to the action; it does not mutate. Resolution: require an Auth0 session (else send to Auth0 and back via `return_to`); authorize the session user as a `household_memberships` member of the link's household (else `403`); resolve the link's `link_tasks` to the actionable task (multi-task routing below); then redirect to the action URL for that task's open occurrence — `GET /occurrences/{id}/execute`.
- `GET /occurrences/{id}/execute` is where the side effect lives: it marks the occurrence done, then renders the occurrence page. It is a `GET` (an NFC tap is a navigation, and the core "tap → done" path must be frictionless) and is safe to reload because it is **occurrence-idempotent** — the id pins one specific occurrence, so a second hit finds it already resolved and just shows it. Re-tapping the *tag* tomorrow will be a different occurrence once recurrence generation is implemented.
- Deferred until Undo is built: a stray reload of `/occurrences/{id}/execute` would re-complete an occurrence that was just undone. The planned fix is that the Undo action (a `POST`, explicit button) redirects to the inert `/occurrences/{id}` show page, so after an undo you are no longer sitting on an executing URL. We may move the landing path then; it does not affect the stable `/links/{id}` tag contract.
- A link is re-pointable: changing which task(s) it drives is a web-UI edit of `link_tasks`, never a physical rewrite. This is the whole reason for the indirection given that tag surfaces are painful to change.
- `link_tasks` is a plain join of one `links` row to a task — `(household_id, link_id, task_id)`. A link may drive multiple tasks, and a task may be reachable from multiple links. To stop a link driving a task, delete the row. What an execute *does* is derived from the linked task's `task_type` at execute time, not stored on the binding, so editing a task's type can never leave a stale binding behind. The current execute behavior is `attempt_completion` for `scheduled`/`interval` tasks; planned timer execution will add `toggle_timer` for `timer` tasks.
- When a link drives more than one task, execute considers each linked task's current occurrence whose `[valid_from, expiration_time)` window contains now, ignores completed occurrences while any open occurrence remains, sorts the open occurrences by `due_at`, and acts on the first due occurrence. This lets one physical tag cover related routines while staying deterministic. An execute that matches no task window is treated like an unassigned link and redirects to `/links/:id/status` (e.g. breakfast already expired and dinner not yet at its `valid_from`).
- `attempt_completion` is state-dependent. If the current occurrence is incomplete, it sets `completed_at`/`completed_by_id`. If it was already completed, it does not undo the task; the user simply lands on the occurrence showing it is already done.
- Planned: `toggle_timer` is state-dependent. If no timer occurrence is active, it creates a delayed occurrence (`due_at = now + tasks.interval_minutes`). If a timer is already active, it cancels (deletes) that occurrence.
- For `timer` tasks, `interval_minutes` is the countdown length, e.g. `60` for a laundry move. It lives on the task, not on the binding, so the link stays a pure trigger. This is the same duration field used by `interval` tasks; `task_type` decides whether the duration is applied after completion automatically (`interval`) or only after a user starts a timer (`timer`).
- The execute window is `[tasks.valid_from, tasks.expiration_time)` in the household timezone — start-inclusive, end-exclusive, so `05:00`-`11:00` matches executes at or after 05:00 and before 11:00. `valid_from` is nullable (null = from start of day); `expiration_time` is the single end, shared with planned occurrence resolution (no separate window-end column). If `expiration_time` is earlier than `valid_from`, the window crosses midnight. `interval` tasks leave both null and are tappable all day until done.

## Retention

Old task history will be deleted from `task_occurrences`. `notification_deliveries` rows are scoped to a `task_occurrence` and their foreign key uses `ON DELETE CASCADE`, so deleting an old occurrence also deletes its delivery records. This keeps retention simple: the app can delete occurrences older than the configured retention window without leaving orphaned delivery attempts. The upsert (one row per occurrence+recipient+type) keeps the table small in the meantime.

## Notification Tables

`notification_deliveries` is current-state, not an append log: exactly one row per
`(task_occurrence_id, user_id, notification_type)`, upserted on each send.
`notification_type` is `"reminder"` today (`"completed"` reserved). `reminder_count`
and `last_sent_at` drive cadence and per-recipient quiet-hours gating; `last_status`
records the most recent send outcome (`ok`/`error`). See [scheduling.md](scheduling.md)
and [decisions.md](decisions.md).

```mermaid
erDiagram
    task_occurrences ||--o{ notification_deliveries : notifies_about
    users ||--o{ notification_deliveries : receives

    notification_deliveries {
        uuid id PK
        uuid task_occurrence_id FK
        uuid user_id FK
        string notification_type
        datetime last_sent_at
        integer reminder_count
        string last_status
        datetime inserted_at
        datetime updated_at
    }
```
