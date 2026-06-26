Gaps I see (prioritized)

1. NFC ingestion API contract — the one you flagged. Hard to change once tags are written. Should be locked first. ← let's do this now.
2. Sequence diagram for scan → resolve command → record event → notify (request/response level, not just the component flow you have).
3. Domain/base-URL decision — the host baked into tags is also painful to change, separately from the path.
4. Occurrence generation + reminders — the DB shape is defined but nothing documents who creates task_occurrences and fires reminders (Oban job? cron? schedule?).
5. Stack/ADR doc — repo calls itself a monorepo but the stack (Phoenix/Ecto/Oban, Auth0) is only implied. One short decisions file would anchor it.
6. Web UI routes — low priority, since you correctly note those are cheap to change.


- Add an expiration_time field to task occurrences, so each occurrence can expire after a set cutoff.
- Look up the guidance around Ecto datetime from the cars_platform PR template.
