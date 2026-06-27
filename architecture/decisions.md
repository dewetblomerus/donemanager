# Decisions

Informal running log of choices and why. Newest first.

## Open question: notifications during quiet hours

Direction, not settled for V1 — captured so it doesn't block. Quiet hours decide *how loud*, not a hard send/skip: priority is chosen in the Pushover-sending code from the recipient's `users.quiet_hours_*`, which keeps the scheduler's notify decision simple.

- Completion confirmations go to all recipients always; during a recipient's quiet hours they go out silently (Pushover low priority, -1) so an insomniac doing chores at 3am informs the household without waking anyone.
- Overdue reminders generally should *not* fire during quiet hours (the mop water can wait till morning), but some time-sensitive chores (laundry → dryer) may warrant a silent overnight reminder.
- Still open: per-task time-sensitivity (which chores override quiet hours), and overnight reminder cadence (avoiding a pile-up of silent notifications).

The V1 model already enables this with no table/column changes: `notification_deliveries.notification_type` separates confirmations from reminders, per-user `quiet_hours_*` drive priority, and `task_events` records each send. The only future addition a time-sensitivity rule might need is one nullable per-task flag — an additive, safe-to-add-later column, not a restructuring.

## App structure: single Phoenix monolith in a monorepo

One Phoenix app, 100% monolith — no umbrella. Less ceremony for a solo, low-maintenance project. The repo stays a monorepo so future sibling directories can live alongside the app: `architecture/`, `terraform/`, `marketing-site`/`website`, `android-app`, `ios-app`. "Monorepo" means one repo for these pieces, not an Elixir umbrella.

## Scan feedback latency is a priority

The time from scanning an NFC tag to the scanner seeing confirmation matters more than at-least-once delivery on that path. Lean: resolve the outcome from reads, return/show it immediately, then persist (task_event, occurrence changes, notifications to others) asynchronously and best-effort. `integration_bearer_tokens.last_used_at` is the clearest best-effort case — at-most-once, fire-and-forget, deferred until token management exists (see [stages.md](stages.md)).

Open, pending hands-on testing of NFC Tasks: whether the scanner's ack is the **HTTP response body** (lowest latency, but may need per-tag display config in NFC Tasks) or a **Pushover to the scanner** (no per-tag config, extra round-trip). Also unresolved: `TOGGLE_TIMER` occurrence-creation may need durable (synchronous) writes since a lost write means a missed reminder, unlike a lost completion which self-heals. Decide once tags exist to test with.

## Datetimes: `utc_datetime_usec` for instants, `Time` for wall-clock

All instant columns use `utc_datetime_usec` (UTC), not `naive_datetime`: Ecto enforces `Etc/UTC` and errors on anything else, so a local time can't silently slip in — validation, not convention. `_usec` avoids truncating `DateTime.utc_now()`. Centralize via `config.exs` migration timestamp type plus a shared schema module's `timestamps_opts`, applied everywhere. Postgres column is `timestamptz`.

Wall-clock time-of-day columns (`tasks.due_time`, `tasks.expiration_time`, `users.quiet_hours_start/end`) stay `Time` — they are not instants. They are interpreted in `households.timezone` when an occurrence is generated or a reminder is evaluated. ([Background](https://elixirforum.com/t/why-use-utc-datetime-over-naive-datetime-for-ecto/32532).)

## API host domain: deferred

The `{api_host}` baked into NFC tags (see [api.md](api.md)) is decided when the domain name is bought. It will be a dedicated API subdomain so the web UI can move without rewriting tags. No tags get written until it's chosen.

## Scheduling: Oban cron + reconcile loop

Occurrence generation and reminders run as one Oban cron job every minute that reconciles from DB state (see [scheduling.md](scheduling.md)). Oban over a hand-rolled GenServer/Quantum because it's Postgres-backed (no Redis), survives restarts, guarantees single concurrent execution across deploy overlap, and is stable + well-represented in LLM training data. A GenServer only looks simpler — it pushes singleton/retry/restart correctness onto us, the kind of code a vibe-coder can't afford to debug.

Oban is at-least-once, not exactly-once; effectively-once comes from idempotent reconciliation (reminders gated on recorded `reminder_sent` events). Worker is `unique` over non-terminal states with a single-slot queue, so an overrunning run skips the next tick instead of piling up — safe because the loop recomputes from state.

## Multitenancy: Phoenix Scopes

Use Phoenix 1.8 [Scopes](https://phoenix.hexdocs.pm/scopes.html) for household isolation. Auth is Auth0 via Ueberauth, so we never run `mix phx.gen.auth` (it scaffolds Phoenix's own password auth). Scopes don't need it: define the `Scope` module by hand, configure `config :phoenix, :scopes` with `schema_key: household_id`, and build the scope from the Auth0 session (`users.auth0_sub` → user → household) in a plug / `on_mount` that assigns `:current_scope`. The context and LiveView generators then thread it. Scopes are a mandatory first argument to every data function (`list_tasks(scope)`, `get_task!(scope, id)`), which makes cross-household access structurally impossible rather than something to remember per query — directly addressing OWASP broken-access-control. This is the guardrail that makes skipping Ash safe. Back it with a couple of cross-household isolation tests early.

## No Ash framework

Plain Phoenix contexts + generators, not Ash. The project is vibe-coded without carefully reading the code, so it depends on the generator being reliably correct — and vanilla Phoenix/Ecto is far more densely represented in LLM training data than Ash's fast-moving DSL. When generated code breaks, plain Elixir is readable top-to-bottom; Ash failures are framework-magic failures that require deep DSL knowledge to debug, which conflicts with not reading code. Ash also adds a large coupled dependency cluster, cutting against the upgrade-churn goal behind the Phoenix + LiveView choice.

Ash's free GraphQL/JSON:API is real but discounted: productizing + mobile is ~20% likely, a JSON API is cheap to add to plain Phoenix later, and NFC ingestion is already a hand-written JSON endpoint. Its strongest fit — declarative multitenancy — is covered by Phoenix Scopes instead. Would flip if productizing were >50% likely, since retrofitting Ash later is a real rewrite.

## Stack: Phoenix + LiveView

Chosen for lowest long-term maintenance as a solo, low-attention project meant to run for years with a few families using it. The dominant cost over that horizon is package upgrades, and LiveView minimizes it:

- No JavaScript build chain to own — Phoenix vendors esbuild + Tailwind and server-renders HTML. This is the part of a React stack that rots fastest.
- One dependency tree and one language, not a separate Python API tree plus an npm tree.
- BEAM covers the moving parts this app needs in one runtime: Oban for occurrence generation and reminders, Phoenix PubSub for realtime web updates.

FastAPI + React was considered. Its larger ecosystem buys nothing here — the integrations (Auth0/OIDC, Pushover HTTP, NFC HTTP ingestion, Postgres/Ecto) are all well covered in Elixir — while costing a second language and build chain, which cuts against the maintenance goal.

Trade-offs accepted: smaller contributor pool; a stateful always-on server (no scale-to-zero); a future native mobile app would be less direct (mitigated — NFC ingestion is already a plain JSON endpoint).
