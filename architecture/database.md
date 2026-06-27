# Database

This is the proposed V1 database shape for Done Manager.

## Entity Relationship Diagram

```mermaid
erDiagram
    households ||--o{ household_memberships : has
    users ||--o{ household_memberships : joins
    users ||--o{ integration_bearer_tokens : owns
    users ||--o{ integration_bearer_tokens : creates
    households ||--o{ integration_bearer_tokens : authorizes
    users ||--o{ pushover_destinations : owns
    households ||--o{ tasks : owns
    households ||--o{ nfc_tags : owns
    households ||--o{ automation_commands : owns
    tasks ||--o{ automation_commands : receives
    nfc_tags ||--o{ automation_commands : invokes
    tasks ||--o{ task_occurrences : schedules
    task_occurrences ||--o{ task_events : records
    task_occurrences ||--o{ notification_deliveries : notifies_about
    users ||--o{ task_events : performs
    nfc_tags ||--o{ task_events : source
    automation_commands ||--o{ task_events : produces
    integration_bearer_tokens ||--o{ task_events : authenticates
    pushover_destinations ||--o{ notification_deliveries : receives

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
        string email
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

    integration_bearer_tokens {
        uuid id PK
        uuid household_id FK
        uuid user_id FK
        uuid created_by_user_id FK
        string label
        string prefix
        string token_hash
        string source
        datetime revoked_at
        datetime last_used_at
        datetime inserted_at
        datetime updated_at
    }

    pushover_destinations {
        uuid id PK
        uuid user_id FK
        string label
        string pushover_user_key
        string pushover_device
        boolean enabled
        datetime inserted_at
        datetime updated_at
    }

    tasks {
        uuid id PK
        uuid household_id FK
        string name
        string description
        string task_type
        string cadence_frequency
        string[] cadence_weekdays
        integer cadence_interval_minutes
        time due_time
        time expiration_time
        integer reminder_interval_minutes
        boolean active
        datetime inserted_at
        datetime updated_at
    }

    task_occurrences {
        uuid id PK
        uuid task_id FK
        date occurrence_date
        datetime due_at
        datetime expires_at
        datetime inserted_at
    }

    nfc_tags {
        uuid id PK
        uuid household_id FK
        string label
        string external_id
        boolean active
        datetime last_scanned_at
        datetime inserted_at
        datetime updated_at
    }

    automation_commands {
        uuid id PK
        uuid household_id FK
        uuid task_id FK
        uuid nfc_tag_id FK
        string label
        string command_type
        json config
        boolean active
        datetime inserted_at
        datetime updated_at
    }

    task_events {
        uuid id PK
        uuid task_occurrence_id FK
        uuid user_id FK
        uuid nfc_tag_id FK
        uuid automation_command_id FK
        uuid integration_bearer_token_id FK
        string event_type
        string source
        datetime occurred_at
        datetime inserted_at
    }

    notification_deliveries {
        uuid id PK
        uuid task_occurrence_id FK
        uuid pushover_destination_id FK
        string notification_type
        string status
        datetime sent_at
        datetime inserted_at
        datetime updated_at
    }
```

## Authentication Model

Browser users authenticate through Auth0. The `users.auth0_sub` field stores the stable Auth0 subject and maps the external identity to the app user.

External integrations use bearer tokens. NFC Tasks is the first integration, but the same model can support QR-code flows, Arduino buttons, Home Assistant, or other automation clients. Each token belongs to a household and may map back to a `users` row when the integration should act on behalf of a person.

Bearer tokens should be stored with a lookup `prefix` and a `token_hash`, scoped to integration-event endpoints, and revocable per device or integration. The full token should only be shown once when created. Requests should extract the prefix, load the non-revoked token row, then verify the full bearer token against `token_hash`.

Only a household owner can create integration bearer tokens for that household. Token management screens and APIs should enforce the owner's membership role before generating or revoking tokens, and should record the owner in `created_by_user_id`.

Users own their Pushover destinations directly. A user can belong to multiple households and take the same Pushover delivery setup with them. Households decide which users should be notified; each user's Pushover destinations decide where those notifications are delivered.

## Notes

- Primary keys should use UUIDv7.
- Every `datetime` column above is a UTC instant stored as Ecto `utc_datetime_usec` (`timestamptz`). The `time` columns (`due_time`, `expiration_time`, `quiet_hours_start/end`) are wall-clock times of day, not instants, interpreted in `households.timezone`. See [decisions.md](decisions.md).
- `households` is included even if V1 only has one household. It keeps ownership explicit without adding much complexity.
- `households.timezone` is the single timezone for household-local routines.
- `users.quiet_hours_start` and `quiet_hours_end` are per-user times (interpreted in the household timezone) bounding when that user may receive reminders. They are per-user from V1 because household members keep different sleeping hours. Overdue reminders are suppressed during a user's quiet hours and resume when their window reopens, so a task that goes overdue overnight notifies each user once their own waking hours begin. The household decides who is notified; each user's quiet hours decide when, and their Pushover destinations decide where.
- `household_memberships.role` can start simple, such as `owner` or `member`.
- Only users with an `owner` household membership can create integration bearer tokens for that household.
- `pushover_destinations` is intentionally Pushover-specific. If other notification integrations are added later, they can get their own tables first.
- `tasks` stores the task definition, behavior type, and cadence, such as `Spot breakfast` due daily by 11:00 in the household's timezone.
- `task_type` is the occurrence-generation strategy, the switch the generator branches on. V1 values: `SCHEDULED` (pre-generated per date from a wall-clock cadence), `INTERVAL` (rolled forward at completion, anchored to the last `completed` event), and `ONE_OFF` (created on scan by a command such as a laundry timer). Each type owns its own columns: `SCHEDULED` uses `cadence_frequency`, `cadence_weekdays`, `due_time`, `expiration_time`; `INTERVAL` uses `cadence_interval_minutes`; `ONE_OFF` carries its delay in the command's `config`.
- For `SCHEDULED` tasks, cadence uses normalized columns that intentionally mirror a small iCalendar RRULE subset. `cadence_frequency` uses uppercase constants `DAILY` or `WEEKLY` (null for `INTERVAL` and `ONE_OFF`). `cadence_weekdays` uses uppercase iCalendar weekday tokens such as `MO`, `TU`, `WE`, `TH`, `FR`, `SA`, and `SU`.
- For V1, `cadence_weekdays` should be empty for `DAILY` tasks and non-empty for `WEEKLY` tasks. Future recurrence complexity can grow from this shape with columns such as `cadence_interval`, `cadence_monthdays`, `cadence_until`, or `cadence_count`.
- `INTERVAL` (floating) tasks are due relative to their last completion, not a calendar slot, so `cadence_frequency` is null. `cadence_interval_minutes` is the gap, e.g. `180` for a 3-hour "let the dog out" task or `2880` for a 48-hour "empty the robot mop" task. The next occurrence's `due_at` is the latest `completed` `task_event` plus the interval; a scan at any time records a `completed` event and rolls the clock forward, so doing it early pushes the next due-time out. `ATTEMPT_COMPLETION` on an `INTERVAL` task always records `completed` and resets — there is no per-date duplicate state. `cadence_interval_minutes` is distinct from the RRULE-style `cadence_interval` mentioned above, which would mean "every N periods" for a future `SCHEDULED` cadence.
- `tasks.reminder_interval_minutes` (nullable) controls re-notification of an overdue occurrence: the backend keeps sending reminders at this cadence — each recorded as a `reminder_sent` `task_event` — until the occurrence is completed, skipping each recipient's quiet hours. Null means a single reminder.
- `tasks.due_time` and nullable `tasks.expiration_time` are `Time` values — household-local times of day, not instants. If `expiration_time` is blank, generated occurrences do not expire by cutoff.
- `task_occurrences` stores each concrete expected instance, such as `Spot breakfast for 2026-06-25`. `due_at` is when the task is due, and nullable `expires_at` is the concrete cutoff after which the occurrence should no longer be treated as the current actionable occurrence. Both are UTC instants (`utc_datetime_usec`), resolved from the task's wall-clock `due_time`/`expiration_time` in `households.timezone` at generation time.
- When generating a recurring occurrence, if `expiration_time` is later than `due_time`, `expires_at` is on the same local date as `due_at`. If `expiration_time` is less than or equal to `due_time`, `expires_at` is on the next local date. For example, a task due at 22:00 with `expiration_time` 02:00 expires at 02:00 the next day.
- `task_occurrences` should not store status. Status is derived from related `task_events`.
- `nfc_tags` represents physical or integration inputs owned by a household, not tasks. The NFC action sends an opaque `external_id` with an integration bearer token; the backend resolves that input to a configured command. See [API](api.md) for the scan contract.
- `nfc_tags.external_id` is a client-generated UUIDv7 written onto the tag, unique per household via an index on (`household_id`, `external_id`). The first scan of an unknown id provisions the tag (find-or-create, active and unassigned), so a user can scan a fresh tag and then assign it in the web UI. UUIDv7 keeps the upsert collision-safe; human naming lives in `label`.
- `nfc_tags.last_scanned_at` records the most recent scan, including scans of unassigned tags that produce no `task_event`.
- `automation_commands` maps an input to task-specific intent. `label` is the UI/admin name for the configured command, such as `Dog food bin scan` or `Washer timer`. V1 command types can start with `ATTEMPT_COMPLETION` and `TOGGLE_TIMER`.
- `ATTEMPT_COMPLETION` is state-dependent. If the current occurrence is incomplete, the command can produce a `completed` event. If it was already completed, it should not undo the task; it can produce a `duplicate_completion_attempted` event and notify the scanner.
- `TOGGLE_TIMER` is state-dependent. If no timer occurrence is active, the command can create a delayed occurrence and produce a `timer_started` event. If the timer is already active, it can cancel that occurrence and produce a `timer_cancelled` event.
- `automation_commands.config` stores command-specific settings, such as `{ "delay_minutes": 60 }` for a laundry timer.
- `task_events.event_type` can represent outcomes such as `completed`, `duplicate_completion_attempted`, `timer_started`, `timer_cancelled`, `acknowledged`, `reminder_sent`, or `skipped`.
- `task_events.source` can represent whether the event came from `nfc`, `web`, or a system process.
- Acknowledgements are task events, not a separate table.
- Anonymous physical acknowledgements can be recorded as task events through an integration token without a `user_id`, such as `acknowledged by Arduino button press`.
- `notification_deliveries` records Pushover delivery attempts and can include durable task links in the sent message body without storing separate magic-link tokens.

## Retention

Old task history is deleted from `task_occurrences`.

`task_events` and `notification_deliveries` are scoped to a `task_occurrence`, not directly to a task. Foreign keys from those tables to `task_occurrences` should use `ON DELETE CASCADE`, so deleting an old occurrence also deletes its event log and notification delivery records.

This keeps retention simple: the app can delete occurrences older than the configured retention window without leaving orphaned events or delivery attempts.
