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

## Stage 2 — Smallest vertical slice: tap completes a task

The thinnest real path through the domain: create a task in the web UI, tap its link, the task shows as done. No notifications, no reminders, no Oban yet — the web UI creates the task and its first occurrence eagerly, and the link execute completes it.

Tables (on top of stage 1):

5. `tasks` (households)
6. `links` (households)
7. `link_tasks` (links, tasks) — the join that binds a link to a task; the execute behaviour is derived from the task's type (`attempt_completion` here)
8. `task_occurrences` (tasks) — completion stored on the row (`completed_at`, `completed_by_id`)

There is no `integration_bearer_tokens` and no `task_events` table — authorization is the Auth0 session + household membership, and completion status lives on the occurrence.

Architecture to honour even in the slice:
- Scope every query by `household_id` via Phoenix Scopes from the start.
- The tag follows the stable contract `GET /links/{id}` ([database.md](database.md) `links` notes): require a session, authorize household membership, resolve the open occurrence, and redirect to `GET /occurrences/{id}/execute`, which marks it done and renders the occurrence page.
- Status is read from `task_occurrences.completed_at`, not a status column.

Testable outcome: a signed-in member taps `/links/{id}`, gets redirected to `/occurrences/{id}/execute`, the occurrence's `completed_at`/`completed_by_id` are set, and the web UI reflects done — provable end to end without any push or scheduler. A non-member gets `403`; reloading the execute URL is idempotent and does not double-complete.

## Deferred to later stages

- Generation: the Oban reconcile loop and the single-invariant occurrence lifecycle (see [scheduling.md](scheduling.md)). Until then, the first occurrence is created eagerly.
- `scheduled` and `interval` task types: the slice uses one task with an eagerly-created occurrence; recurrence comes with the reconcile loop.
- Notifications: `pushover_destinations`, `notification_deliveries`, quiet hours, and reminders.
- `timer` task type and the `toggle_timer` behaviour.
- Multi-task links and execute-window routing.
