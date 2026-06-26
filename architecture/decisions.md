# Decisions

Informal running log of choices and why. Newest first.

## Stack: Phoenix + LiveView

Chosen for lowest long-term maintenance as a solo, low-attention project meant to run for years with a few families using it. The dominant cost over that horizon is package upgrades, and LiveView minimizes it:

- No JavaScript build chain to own — Phoenix vendors esbuild + Tailwind and server-renders HTML. This is the part of a React stack that rots fastest.
- One dependency tree and one language, not a separate Python API tree plus an npm tree.
- BEAM covers the moving parts this app needs in one runtime: Oban for occurrence generation and reminders, Phoenix PubSub for realtime web updates.

FastAPI + React was considered. Its larger ecosystem buys nothing here — the integrations (Auth0/OIDC, Pushover HTTP, NFC HTTP ingestion, Postgres/Ecto) are all well covered in Elixir — while costing a second language and build chain, which cuts against the maintenance goal.

Trade-offs accepted: smaller contributor pool; a stateful always-on server (no scale-to-zero); a future native mobile app would be less direct (mitigated — NFC ingestion is already a plain JSON endpoint).
