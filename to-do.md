Gaps I see (prioritized)



4. Occurrence generation + reminders — the DB shape is defined but nothing documents who creates task_occurrences and fires reminders (Oban job? cron? schedule?).
5. Stack/ADR doc — repo calls itself a monorepo but the stack (Phoenix/Ecto/Oban, Auth0) is only implied. One short decisions file would anchor it.

- Look up the guidance around Ecto datetime from the cars_platform PR template.
