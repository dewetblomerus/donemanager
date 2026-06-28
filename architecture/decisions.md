# Decisions

Informal running log of choices and why. Newest first.

## One-time pre-launch migration reset

The link redesign was applied by **editing the existing migrations in place** rather than adding new ones, and the prod DB is dropped before the next deploy. Safe only because we are pre-launch with no real data: every environment starts fresh, so the migration history reads as a clean description of the destination instead of a rename/drop archaeology trail. This is a one-time move — the moment a real user exists in prod, migrations are additive-only again.

## NFC carries a public link, not a secret

The Android NFC tooling can't keep a secret separate from what's written to the tag — anything on the tag is public to anyone who scans it. So the bearer-token-on-device model is dead. A tag now carries only a public URL, `GET /links/{id}`, that opens in the phone browser. Authorization comes from the **Auth0 session + household membership**, attribution from the session user. The id is the `links` row's UUIDv7 PK (no `external_id` — that only existed because a tag writer used to mint the id); it's a deep-link target, not a credential.

Consequences, all reflected in [database.md](database.md):
- **Dropped** `integration_bearer_tokens` and `task_events`. A future non-browser client (Home Assistant, Arduino) can reintroduce a token table when it actually exists.
- **Renamed** `nfc_tags` → `links` (slimmed: no `external_id`, no `last_scanned_*`) and `automation_commands` → `link_tasks` (a plain `(household_id, link_id, task_id)` join — no `label`, no `active`; deactivate by deleting the row).
- **Completion status moves onto `task_occurrences`** (`completed_at`, `completed_by_id`), reversing the old "status derived from `task_events`, never stored" rule — that rule depended on the dropped table.
- **The tag URL `GET /links/{id}` resolves and redirects to `GET /occurrences/{id}/execute`, which marks done and renders the occurrence.** Execution is occurrence-idempotent — the id pins one occurrence, so reload / double-tap just re-renders "done." A `GET` with a side effect is safe because it's auth-gated and idempotent. The old "opening a link does nothing, only the button press acts" rule was for unauthenticated remote ack and is no longer needed — the session is the gate. Deferred to Undo: the Undo action (a `POST`) will redirect to the inert `/occurrences/{id}` show page so a reload can't re-fire after an undo; the stable `/links/{id}` tag contract is unaffected.
- `tasks.scan_window_*` renamed to `tasks.execute_window_*`.
- `api.md` is deleted — there's no JSON API now; the one stable contract (the tag URL) lives in the `database.md` `links` notes.
- **MVP is routine management only — no Pushover send path.** Notifications (`pushover_destinations`, `notification_deliveries`, reminders, quiet hours) are post-MVP.

## One occurrence lifecycle: exactly one open occurrence

`scheduled` and `interval` tasks share a single invariant: a task has exactly one open occurrence; when it resolves (`completed_at` set **or** `expires_at < now`), the loop creates the next. No rolling-horizon pre-generation; future occurrences are computed for display, not stored. The only per-type code is the next-`due_at` formula (calendar slot vs last completion + interval). See [scheduling.md](scheduling.md).

This drove two sub-decisions:
- **A `scheduled` task must set `expiration_time`** (changeset constraint), so a missed slot resolves by expiring and doesn't block the next slot — a forgotten breakfast must not suppress dinner. We couldn't think of a calendar-anchored task that should stay open forever; easy to loosen later, hard to add.
- **`interval` tasks never expire** (`expires_at = null`): they stay open and grow more overdue ("3 days overdue") until done, then roll forward. This is what makes "why is the plant dying" answerable — the completed chain is honest history with no pile-up of missed rows.
- **No `occurrence_date` column.** It was only ever a generation key; the invariant keys on resolution instead (uniqueness guard on `(task_id, due_at)`). The local date is derived from `due_at` for display.

## UI: stock Phoenix generator conventions, no custom design

Use the `mix phx.gen.*` HTML/LiveView output and `core_components` as-is — default layout, tables, forms, flash. No bespoke styling or design system. Custom design is wasted effort for a few-family internal tool, and staying on generator conventions keeps the app legible to the generators and to LLMs (the vibe-coding bet) and cuts upgrade churn. Revisit only if the app is ever productized.

## Scope carries current_household from day one

The `Scope` holds a `current_household` from the first commit, even though the household-switcher UI is deferred and early users have one household. Retrofitting a tenant key into every query later is far-reaching and error-prone, and multi-household is plausible early (friends asking to be added) even if the app never grows past a few households.

Mostly this is a security stance: Auth0 self-signup is authentication, not authorization. Anyone can sign themselves up, so a freshly signed-up user with no membership must see nothing — default-deny. A user can only ever act within households they are a verified `household_memberships` member of, and `current_household` must be one of them. Building this from day one (via Phoenix [Scopes](https://phoenix.hexdocs.pm/scopes.html), [decided below](#multitenancy-phoenix-scopes)) makes cross-household access structurally impossible rather than a check that can be forgotten. A bad actor signing up gets an empty app, not a window into other households' data.

## Open question: notifications during quiet hours

Direction, not settled for V1 — captured so it doesn't block. Quiet hours decide *how loud*, not a hard send/skip: priority is chosen in the Pushover-sending code from the recipient's `users.quiet_hours_*`, which keeps the scheduler's notify decision simple.

- Completion confirmations go to all recipients always; during a recipient's quiet hours they go out silently (Pushover low priority, -1) so an insomniac doing chores at 3am informs the household without waking anyone.
- Overdue reminders generally should *not* fire during quiet hours (the mop water can wait till morning), but some time-sensitive chores (laundry → dryer) may warrant a silent overnight reminder.
- Still open: per-task time-sensitivity (which chores override quiet hours), and overnight reminder cadence (avoiding a pile-up of silent notifications).

The model already enables this with no table/column changes: `notification_deliveries.notification_type` separates confirmations from reminders, per-user `quiet_hours_*` drive priority, and each `notification_deliveries` row records a send. The only future addition a time-sensitivity rule might need is one nullable per-task flag — an additive, safe-to-add-later column, not a restructuring. (Notifications are post-MVP regardless.)

## App structure: single Phoenix monolith in a monorepo

One Phoenix app, 100% monolith — no umbrella. Less ceremony for a solo, low-maintenance project. The mix project lives in `app/`. The repo stays a monorepo so future sibling directories can live alongside it: `architecture/`, `terraform/`, `marketing-site`/`website`, `android-app`, `ios-app`. "Monorepo" means one repo for these pieces, not an Elixir umbrella.

CI runs `mix check` (ex_check) via the shared [dewetblomerus/actions-elixir](https://github.com/dewetblomerus/actions-elixir) reusable workflow with `working-directory: app`. The check policy (Credo, Sobelow, format, warnings-as-errors, unused deps, tests) lives in `app/mix.exs` + `app/.check.exs`; `mix_audit` is a separate informational check. Sobelow's `Config.CSP` finding is ignored for now — adding a Content-Security-Policy is a deferred hardening step that needs browser testing.

## Tap feedback latency is a priority

The time from tapping a tag to the person seeing confirmation matters. With the browser-link model the ack is concrete: the tap opens `/links/{id}`, which redirects to `/occurrences/{id}/execute` — that completes the occurrence and renders the page, which *is* the confirmation, no extra round-trip and no per-tag display config. Keep the completion write on the request path (it's a single row update) so the redirect reflects truth; defer only other-recipient notifications, which are post-MVP anyway. Superseded the old bearer-token/HTTP-JSON latency analysis. `toggle_timer` occurrence-creation may still want a durable synchronous write since a lost write means a missed reminder; decide once timers are built.

## Datetimes: `utc_datetime_usec` for instants, `Time` for wall-clock

All instant columns use `utc_datetime_usec` (UTC), not `naive_datetime`: Ecto enforces `Etc/UTC` and errors on anything else, so a local time can't silently slip in — validation, not convention. `_usec` avoids truncating `DateTime.utc_now()`. Centralize via `config.exs` migration timestamp type plus a shared schema module's `timestamps_opts`, applied everywhere. Postgres column is `timestamptz`.

Two layers, deliberately. The Ecto `:utc_datetime_usec` *schema type* enforces UTC in app code (its dump step rejects non-UTC), but that lives only in the BEAM — raw SQL, psql, or another writer bypasses it. The `timestamptz` *column* is the database-level guarantee: it stores an absolute instant (always UTC internally) and normalizes any writer's input by their session timezone, so a naive local time can't masquerade as UTC even when Ecto isn't in the path. Keeping both is belt-and-suspenders rather than band-aid-only.

This needs an explicit override: Ecto's `:utc_datetime_usec` maps to `timestamp without time zone` by default (a historical mapping kept for backwards compatibility — changing it would silently alter every existing app's columns). So we set `migration_timestamps: [type: :timestamptz]` (and `:timestamptz` on any standalone instant column like `household_invitations.expires_at`) while the schema field stays `:utc_datetime_usec`. Verify with `information_schema.columns` — instant columns should read `timestamp with time zone`; `schema_migrations` stays plain `timestamp` since Ecto owns it.

Wall-clock time-of-day columns (`tasks.due_time`, `tasks.expiration_time`, `users.quiet_hours_start/end`) stay `Time` — they are not instants. They are interpreted in `households.timezone` when an occurrence is generated or a reminder is evaluated. ([Background](https://elixirforum.com/t/why-use-utc-datetime-over-naive-datetime-for-ecto/32532).)

## Tag host domain

`donemanager.com` is purchased. Tags now bake the web-app link `https://app.donemanager.com/links/{id}`, not a separate API subdomain — superseding the earlier `api.donemanager.com` decision, since there is no JSON API and the tag opens the browser app directly. Whatever host the tag carries is the permanent dependency: it must resolve and the apex must stay renewed for as long as any tag is in use. The route is a server-controlled redirect, so the app can move behind that host without rewriting tags.

## Scheduling: Oban cron + reconcile loop

Occurrence generation and reminders run as one Oban cron job every minute that reconciles from DB state (see [scheduling.md](scheduling.md)). Oban over a hand-rolled GenServer/Quantum because it's Postgres-backed (no Redis), survives restarts, guarantees single concurrent execution across deploy overlap, and is stable + well-represented in LLM training data. A GenServer only looks simpler — it pushes singleton/retry/restart correctness onto us, the kind of code a vibe-coder can't afford to debug.

Oban is at-least-once, not exactly-once; effectively-once comes from idempotent reconciliation (generation gated on "one open occurrence, create next on resolve"; reminders gated on recorded `notification_deliveries` rows). Worker is `unique` over non-terminal states with a single-slot queue, so an overrunning run skips the next tick instead of piling up — safe because the loop recomputes from state.

## Multitenancy: Phoenix Scopes

Use Phoenix 1.8 [Scopes](https://phoenix.hexdocs.pm/scopes.html) for household isolation. Auth is Auth0 via Ueberauth, so we never run `mix phx.gen.auth` (it scaffolds Phoenix's own password auth). Scopes don't need it: define the `Scope` module by hand, configure `config :phoenix, :scopes` with `schema_key: household_id`, and build the scope from the Auth0 session (`users.auth0_sub` → user → household) in a plug / `on_mount` that assigns `:current_scope`. The context and LiveView generators then thread it. Scopes are a mandatory first argument to every data function (`list_tasks(scope)`, `get_task!(scope, id)`), which makes cross-household access structurally impossible rather than something to remember per query — directly addressing OWASP broken-access-control. This is the guardrail that makes skipping Ash safe. Back it with a couple of cross-household isolation tests early.

## No Ash framework

Plain Phoenix contexts + generators, not Ash. The project is vibe-coded without carefully reading the code, so it depends on the generator being reliably correct — and vanilla Phoenix/Ecto is far more densely represented in LLM training data than Ash's fast-moving DSL. When generated code breaks, plain Elixir is readable top-to-bottom; Ash failures are framework-magic failures that require deep DSL knowledge to debug, which conflicts with not reading code. Ash also adds a large coupled dependency cluster, cutting against the upgrade-churn goal behind the Phoenix + LiveView choice.

Ash's free GraphQL/JSON:API is real but discounted: productizing + mobile is ~20% likely, and a JSON API is cheap to add to plain Phoenix later. Its strongest fit — declarative multitenancy — is covered by Phoenix Scopes instead. Would flip if productizing were >50% likely, since retrofitting Ash later is a real rewrite.

## Stack: Phoenix + LiveView

Chosen for lowest long-term maintenance as a solo, low-attention project meant to run for years with a few families using it. The dominant cost over that horizon is package upgrades, and LiveView minimizes it:

- No JavaScript build chain to own — Phoenix vendors esbuild + Tailwind and server-renders HTML. This is the part of a React stack that rots fastest.
- One dependency tree and one language, not a separate Python API tree plus an npm tree.
- BEAM covers the moving parts this app needs in one runtime: Oban for occurrence generation and reminders, Phoenix PubSub for realtime web updates.

FastAPI + React was considered. Its larger ecosystem buys nothing here — the integrations (Auth0/OIDC, Pushover HTTP, Postgres/Ecto) are all well covered in Elixir — while costing a second language and build chain, which cuts against the maintenance goal.

Trade-offs accepted: smaller contributor pool; a stateful always-on server (no scale-to-zero); a future native mobile app would be less direct (mitigated — a JSON API is cheap to add to plain Phoenix later).
