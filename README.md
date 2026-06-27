# Done Manager

A monorepo for a home routine coordination platform.

## Problem

Everyday household questions create friction:

- Have you fed the dog?
- Have you given Bobby his morning meds?
- Has the dog been outside recently?

Coordinating these routines often means opening messaging apps, crafting messages, reading replies, and hoping everyone saw the latest update.

## Solution

A central backend coordinates routine tasks for the household.

- Log who completed a task and when.
- Scan an NFC tag, such as one on the dog food container, to mark a task done.
- Notify everyone when a task is completed.
- Remind everyone when a task is not done by a certain time.
- Let one person acknowledge a task so everyone knows it is handled.
- If someone missed a notification, scanning the NFC tag before acting can immediately show that the task was already done, when, and by whom.

## Layout

This is a monorepo. The Phoenix application lives in `app/` (a single monolith — see [decisions](architecture/decisions.md)). Other top-level directories are reserved for future siblings such as `terraform/`, a marketing site, and native apps.

```
app/            Phoenix monolith (mix project)
architecture/   design docs
.github/        shared CI (calls dewetblomerus/actions-elixir)
```

## Architecture

See [architecture/README.md](architecture/README.md) for the high-level system diagram and current architecture notes.

## CI

GitHub Actions runs `mix check` via the shared [dewetblomerus/actions-elixir](https://github.com/dewetblomerus/actions-elixir) reusable workflow, pointed at `app/`. The check suite (compile-warnings-as-errors, formatter, Credo, Sobelow, unused deps, tests) is defined locally in `app/mix.exs` + `app/.check.exs`; `mix_audit` runs as a separate informational check. Run it locally with `cd app && mix check`.
