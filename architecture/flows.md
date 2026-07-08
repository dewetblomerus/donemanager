# User Flows

Plain-language description of what people do with Done Manager, for a product reader. No database, API, or implementation detail — those live in the other architecture docs. This is the *what it feels like to use*.

## What the app is for

A household tracks shared chores — feeding the dog, moving laundry, emptying the mop — by tapping a phone on an NFC tag stuck near where the chore happens. The tag opens a web page that marks the chore done. Some chores also nag the household until someone does them.

Tapping completes chores, the web app shows what's done and what's due, and overdue chores send push notifications that the household can act on from the notification itself.

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

### A status that follows the clock

A task's status has to reflect *the task right now*, not just the last thing that happened to it. The confusing case is a fixed-schedule chore — afternoon medication — that was done yesterday: the list and the task page must not show a bare "Done", because at a glance that reads as "done today". The web app uses the same vocabulary the tag **status page** shows when someone scans outside the chore's hours, so a task carries one honest status through the day:

- **Not yet** — before the chore's window opens (its `valid_from`). Early morning, the afternoon medication reads "Not yet", not "Done".
- **Open / Overdue** — inside the window and not done. An every-so-often chore that's late reads "Overdue", growing ("3 days overdue").
- **Done** — completed, and it *stays* Done for the rest of that day so an end-of-day glance shows everything finished, even after the window has closed.
- **Missed** — the window closed with nobody doing it (a fixed-schedule chore that expired uncompleted).

When the local day rolls over at midnight, the day resets: a chore that was Done or Missed yesterday goes back to "Not yet" (or "Open" if its window is already open) for today's run. So in the morning every routine reads as open or not-yet, and nothing still claims to be done from yesterday.

**On the task page**, the big status follows the same rule — it never reads a plain "Done" on a later day. The page can still show the *previous* completion as history ("Completed by Sam at 2:14pm yesterday"), but the headline status is today's state, not yesterday's.

**When "Done" flips back: local midnight.** A finished chore reads Done until the local day rolls over — not the moment its window closes — so an end-of-evening glance still shows everything done. (The alternative, flipping at the chore's expiration time, was considered and rejected for that reason.)

## Getting notified

When a chore is overdue, the household gets a push notification (Pushover) nagging them until someone does it. Every member who has set up notifications is reminded; how often a chore re-nags is part of the chore's setup.

- Each person sets up where their notifications go and their quiet hours. Quiet hours are per person, so two people in the same household can sleep on different schedules — a reminder still arrives during someone's quiet hours, but silently, so they simply see it in the morning.
- **The reminder is actionable.** It carries a "Mark done" link, so a person can complete the chore straight from the notification — one tap, no hunting for the tag or the app. They land on the same phone-formatted confirmation page a tag tap shows.
- **A stale reminder is safe.** Notifications linger in the phone's tray, so someone might tap yesterday's reminder today. The link always points at *that* chore — the specific one the reminder was about, never a fresh one for today. If that slot's window has already passed, tapping shows it as **expired** and does *not* mark it done, so a late tap can't quietly claim a missed chore was finished (which could get the dog fed twice).

Completing a chore from afar without a notification is just opening the task in the web app and marking it done — the same authenticated action as a tap, without needing to be near the tag.
