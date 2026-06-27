# User Flows

Plain-language description of what people do with Done Manager, for a product reader. No database, API, or implementation detail — those live in the other architecture docs. This is the *what it feels like to use*.

## What the app is for

A household tracks shared chores — feeding the dog, moving laundry, emptying the mop — by tapping a phone on an NFC tag stuck near where the chore happens. Tapping marks the chore done and lets the rest of the household know. Some chores also nag the household until someone does them.

## Getting started

1. A person signs in (through Auth0).
2. They create a household.
3. They invite another person by typing that person's email address. No email is sent.
4. The invited person signs in and signs up on their own.
5. After signing up, they see the pending invitation and accept it, joining the household.

A person can belong to more than one household.

## Setting up a chore

1. In the web app, a household member creates a task — its name, how it recurs, and when it is due.
2. They place an NFC tag where the chore happens and assign it to the task.
3. A brand-new tag can be tapped first and assigned afterward: the first tap registers the tag, and the web app then offers to attach it to a task.

## Doing a chore (the tap)

1. A person taps their phone on the tag.
2. The chore is marked done, and they immediately see a confirmation that it worked.
3. The rest of the household can be notified that it's done.

A tag can also act as a timer instead of a simple "done" — tapping the laundry tag starts a 60-minute countdown to move the wash to the dryer, and tapping again cancels it.

## The kinds of chores

- **Fixed schedule** — happens at set times, like feeding the dog every morning and evening.
- **On-demand timer** — has no schedule; it starts when someone taps, like the laundry move.
- **Every-so-often** — has no fixed time but becomes due if it hasn't been done in a while, like letting the dog out every few hours or emptying the mop every couple of days. Tapping at any time resets the clock.

## Getting notified

- The household decides who should be notified about a chore. Each person decides where their notifications go and their quiet hours.
- Quiet hours are per person, so two people in the same household can sleep on different schedules. A confirmation that a chore was done still reaches everyone — but silently during a person's quiet hours, so they simply see it in the morning. Someone with insomnia doing chores at 3am won't wake anyone else.
- Reminders for *overdue* chores generally wait until a person's waking hours. A few time-sensitive chores (like moving laundry before it sours) may still send a silent overnight nudge. The exact rules here are still being worked out.
- An overdue "every-so-often" chore keeps reminding until someone does it.

## Acknowledging from afar

When someone gets a notification but isn't near the tag, they can open a link in the notification, sign in if needed, and tap a button to acknowledge the chore. Opening the link alone does nothing — it takes the explicit button press. A physical button (such as an Arduino by the door) can also acknowledge a chore on the household's behalf.
