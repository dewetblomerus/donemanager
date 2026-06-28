# User Flows

Plain-language description of what people do with Done Manager, for a product reader. No database, API, or implementation detail — those live in the other architecture docs. This is the *what it feels like to use*.

## What the app is for

A household tracks shared chores — feeding the dog, moving laundry, emptying the mop — by tapping a phone on an NFC tag stuck near where the chore happens. The tag opens a web page that marks the chore done. Some chores also nag the household until someone does them.

The first release is routine management only: tapping completes chores and the web app shows what's done and what's due. Notifying the rest of the household (push notifications) comes later.

## Getting started

1. A person signs in (through Auth0).
2. They create a household.
3. They invite another person by typing that person's email address. No email is sent.
4. The invited person signs in and signs up on their own.
5. After signing up, they see the pending invitation and accept it, joining the household.

A person can belong to more than one household.

## Setting up a chore

1. In the web app, a household member creates a task — its name, how it recurs, and when it is due.
2. The web app gives them a link for that task. They write the link onto an NFC tag (with NFC Tools) and stick the tag where the chore happens. The same link could go on a printed QR code instead.
3. Re-pointing a tag to a different task later is a change in the web app — the physical tag never has to be rewritten.

The link on the tag is public — it holds no secret. It does nothing on its own; only a signed-in household member can complete a chore with it.

## Doing a chore (the tap)

1. A person taps their phone on the tag, which opens the link in their browser.
2. If they aren't signed in, they sign in once (through Auth0); the browser stays signed in afterward.
3. The chore is marked done and they land on a page confirming it.

Tapping again, reloading, or reopening the page tomorrow does nothing further — the page just shows the chore as already done, so an accidental double-tap is harmless.

A tag can also act as a timer instead of a simple "done" — tapping the laundry tag starts a 60-minute countdown to move the wash to the dryer, and tapping again cancels it.

## The kinds of chores

- **Fixed schedule** — happens at set times, like feeding the dog every morning and evening.
- **On-demand timer** — has no schedule; it starts when someone taps, like the laundry move.
- **Every-so-often** — has no fixed time but becomes due if it hasn't been done in a while, like letting the dog out every few hours or emptying the mop every couple of days. Tapping at any time resets the clock.

## Seeing what's done and what's due

In the web app, the household can see each task's current state — done, due, or overdue — and how overdue it is ("3 days overdue"). An every-so-often chore that nobody has done just keeps showing as more and more overdue until someone does it, and the history of completions shows how often it actually happened.

## Getting notified (later)

Push notifications are a later addition, not in the first release. The intended shape:

- The household decides who should be notified about a chore. Each person decides where their notifications go and their quiet hours.
- Quiet hours are per person, so two people in the same household can sleep on different schedules. A confirmation that a chore was done still reaches everyone — but silently during a person's quiet hours, so they simply see it in the morning.
- Reminders for *overdue* chores generally wait until a person's waking hours, with a few time-sensitive exceptions. The exact rules are still being worked out.

Until then, completing a chore from afar is just opening the task in the web app and marking it done — the same authenticated action as a tap, without needing to be near the tag.
