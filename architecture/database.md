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
    tasks ||--o{ nfc_tags : triggered_by
    tasks ||--o{ task_occurrences : schedules
    task_occurrences ||--o{ task_events : records
    task_occurrences ||--o{ notification_deliveries : notifies_about
    users ||--o{ task_events : performs
    nfc_tags ||--o{ task_events : source
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
        string cadence_type
        time due_time
        boolean active
        datetime inserted_at
        datetime updated_at
    }

    task_occurrences {
        uuid id PK
        uuid task_id FK
        date occurrence_date
        datetime due_at
        datetime inserted_at
    }

    nfc_tags {
        uuid id PK
        uuid task_id FK
        string label
        string external_id
        datetime inserted_at
        datetime updated_at
    }

    task_events {
        uuid id PK
        uuid task_occurrence_id FK
        uuid user_id FK
        uuid nfc_tag_id FK
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
        string pushover_receipt
        datetime sent_at
        datetime inserted_at
        datetime updated_at
    }
```

## Authentication Model

Browser users authenticate through Auth0. The `users.auth0_sub` field stores the stable Auth0 subject and maps the external identity to the app user.

External integrations use bearer tokens. NFC Tasks is the first integration, but the same model can support QR-code flows, Arduino buttons, Home Assistant, or other automation clients. Each token belongs to a household and may map back to a `users` row when the integration should act on behalf of a person.

Bearer tokens should be stored as hashes, scoped to task-event endpoints, and revocable per device or integration.

Only a household owner can create integration bearer tokens for that household. Token management screens and APIs should enforce the owner's membership role before generating or revoking tokens, and should record the owner in `created_by_user_id`.

Users own their Pushover destinations directly. A user can belong to multiple households and take the same Pushover delivery setup with them. Households decide which users should be notified; each user's Pushover destinations decide where those notifications are delivered.

## Notes

- Primary keys should use UUIDv7.
- `households` is included even if V1 only has one household. It keeps ownership explicit without adding much complexity.
- `households.timezone` is the single timezone for household-local routines.
- `household_memberships.role` can start simple, such as `owner` or `member`.
- Only users with an `owner` household membership can create integration bearer tokens for that household.
- `pushover_destinations` is intentionally Pushover-specific. If other notification integrations are added later, they can get their own tables first.
- `tasks` stores the task definition and cadence, such as `Spot breakfast` due daily by 11:00 in the household's timezone.
- `task_occurrences` stores each concrete expected instance, such as `Spot breakfast for 2026-06-25`.
- `task_occurrences` should not store status. Status is derived from related `task_events`.
- `task_events.event_type` can represent events such as `completed`, `acknowledged`, `reminder_sent`, or `skipped`.
- `task_events.source` can represent whether the event came from `nfc`, `web`, or a system process.
- Acknowledgements are task events, not a separate table.
- Anonymous physical acknowledgements can be recorded as task events through an integration token without a `user_id`, such as `acknowledged by Arduino button press`.
- `notification_deliveries` records Pushover delivery attempts and can include durable task links in the sent message body without storing separate magic-link tokens.

## Retention

Old task history is deleted from `task_occurrences`.

`task_events` and `notification_deliveries` are scoped to a `task_occurrence`, not directly to a task. Foreign keys from those tables to `task_occurrences` should use `ON DELETE CASCADE`, so deleting an old occurrence also deletes its event log and notification delivery records.

This keeps retention simple: the app can delete occurrences older than the configured retention window without leaving orphaned events or delivery attempts.
