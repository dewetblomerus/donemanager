# Stages

V1 build order. Each stage is a thin, testable step that follows the [database](database.md) shape so nothing is throwaway. Tables are listed in foreign-key creation order.

## Stage 1 — Accounts and households

Log in (Auth0), create a household, invite someone by email (no email sent), they sign up, then accept the invite.

Tables:

1. `users`
2. `households`
3. `household_memberships` (households, users) — `role` owner/member
4. `household_invitations` (households, users) — an invite targets an `invitee_email` that may not have a user yet, so it can't be a membership row. Columns: `household_id`, `inviter_id`, `invitee_email`, `status`, `expires_at`.

Testable outcome: two users, one household, owner invites by email, invitee signs up and the invite converts to a membership.

## Stage 2 — Smallest vertical slice: scan completes a task

The thinnest real path through the domain: create a task in the web UI, scan an assigned tag, the task shows as done. No notifications, no recurrence generation, no Oban yet — the web UI creates the task and its current occurrence eagerly, and the scan completes it.

Tables (on top of stage 1):

5. `integration_bearer_tokens` (households, users) — authenticates the scan
6. `tasks` (households)
7. `nfc_tags` (households)
8. `automation_commands` (households, tasks, nfc_tags) — `command_type` `ATTEMPT_COMPLETION`
9. `task_occurrences` (tasks)
10. `task_events` (task_occurrences, users, nfc_tags, automation_commands, integration_bearer_tokens)

Architecture to honour even in the slice:
- Scope every query by `household_id` via Phoenix Scopes from the start.
- Occurrence status is derived from `task_events`, never stored.
- The scan endpoint follows the [API](api.md) contract (`POST /v1/tags/{external_id}/scans`, bearer token, find-or-create tag).

Testable outcome: a request to the scan endpoint with a valid token completes the open occurrence, records a `completed` `task_event`, and the web UI reflects done — provable end to end without any push or scheduler.

## Deferred to later stages

- Notifications: `pushover_destinations`, `notification_deliveries`, and async/best-effort write path (see [decisions.md](decisions.md) latency note).
- Scheduling: the Oban reconcile loop for occurrence generation and reminders (see [scheduling.md](scheduling.md)). Until then, occurrences are created eagerly.
- `SCHEDULED` and `INTERVAL` task types: the slice uses one task with an eagerly-created occurrence; recurrence comes with the reconcile loop.
- Token management UI and `integration_bearer_tokens.last_used_at`.
