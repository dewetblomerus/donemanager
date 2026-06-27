# Decisions

Informal running log of choices and why. Newest first.

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

The V1 model already enables this with no table/column changes: `notification_deliveries.notification_type` separates confirmations from reminders, per-user `quiet_hours_*` drive priority, and `task_events` records each send. The only future addition a time-sensitivity rule might need is one nullable per-task flag — an additive, safe-to-add-later column, not a restructuring.

## App structure: single Phoenix monolith in a monorepo

One Phoenix app, 100% monolith — no umbrella. Less ceremony for a solo, low-maintenance project. The mix project lives in `app/`. The repo stays a monorepo so future sibling directories can live alongside it: `architecture/`, `terraform/`, `marketing-site`/`website`, `android-app`, `ios-app`. "Monorepo" means one repo for these pieces, not an Elixir umbrella.

CI runs `mix check` (ex_check) via the shared [dewetblomerus/actions-elixir](https://github.com/dewetblomerus/actions-elixir) reusable workflow with `working-directory: app`. The check policy (Credo, Sobelow, format, warnings-as-errors, unused deps, tests) lives in `app/mix.exs` + `app/.check.exs`; `mix_audit` is a separate informational check. Sobelow's `Config.CSP` finding is ignored for now — adding a Content-Security-Policy is a deferred hardening step that needs browser testing.

## Scan feedback latency is a priority

The time from scanning an NFC tag to the scanner seeing confirmation matters more than at-least-once delivery on that path. Lean: resolve the outcome from reads, return/show it immediately, then persist (task_event, occurrence changes, notifications to others) asynchronously and best-effort. `integration_bearer_tokens.last_used_at` is the clearest best-effort case — at-most-once, fire-and-forget, deferred until token management exists (see [stages.md](stages.md)).

Open, pending hands-on testing of NFC Tasks: whether the scanner's ack is the **HTTP response body** (lowest latency, but may need per-tag display config in NFC Tasks) or a **Pushover to the scanner** (no per-tag config, extra round-trip). Also unresolved: `TOGGLE_TIMER` occurrence-creation may need durable (synchronous) writes since a lost write means a missed reminder, unlike a lost completion which self-heals. Decide once tags exist to test with.

## Datetimes: `utc_datetime_usec` for instants, `Time` for wall-clock

All instant columns use `utc_datetime_usec` (UTC), not `naive_datetime`: Ecto enforces `Etc/UTC` and errors on anything else, so a local time can't silently slip in — validation, not convention. `_usec` avoids truncating `DateTime.utc_now()`. Centralize via `config.exs` migration timestamp type plus a shared schema module's `timestamps_opts`, applied everywhere. Postgres column is `timestamptz`.

Wall-clock time-of-day columns (`tasks.due_time`, `tasks.expiration_time`, `users.quiet_hours_start/end`) stay `Time` — they are not instants. They are interpreted in `households.timezone` when an occurrence is generated or a reminder is evaluated. ([Background](https://elixirforum.com/t/why-use-utc-datetime-over-naive-datetime-for-ecto/32532).)

## API host domain: api.donemanager.com

`donemanager.com` is purchased. NFC tags bake in `https://api.donemanager.com/...` (see [api.md](api.md)) — a dedicated API subdomain so the web UI (`donemanager.com` / `app.donemanager.com`) and the backend host can move without rewriting tags. The apex domain is now the permanent dependency: it must be renewed for as long as any tag is in use.

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
