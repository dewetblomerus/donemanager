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

## Architecture

See [architecture/README.md](architecture/README.md) for the high-level system diagram and current architecture notes.
