---
prio: 60
blocked-by: [feature-track-t-watcher]
---
# Track T face 2: agentic test manager — reads tstate, crafts tickets, owns the T codebase

- **Type:** feature (test infra / agent workflow). Track T (test infra).
- **Opened:** 2026-07-07, from the Track T design discussion (user-approved).

## Concept
A scheduled Claude agent (cron / recurring session) layered over the
standalone watcher (feature-track-t-watcher). The watcher stays dumb and
reliable; the agent adds judgment:

1. **Consume** new `devdocs/progress/tstate/` reports since its last run.
2. **NEW-RED → backlog ticket**, filed like any track's ticket: repro
   command, failing job name, commit range (or exact SHA), first-failure
   log, suspect files from the range diff. Dedupe: one ticket per failing
   job signature; on range narrowing, UPDATE the existing ticket instead of
   filing a new one. Prio default ~70 (regressions block everyone).
3. **Drive bisects:** when a range spans >1 commit, run/schedule the
   single-job bisect (testmgr --job) rather than waiting for idle backfill.
4. **Escalation policy:** core-job red older than a day → mark ticket
   urgent + propose the revert in the ticket body.
5. **Owns the Track T codebase** long-term: testmgr.py, twatch.py, report
   format, tier composition (e.g. promote new corpus targets into full),
   calibration constants. SELF-DIRECTED (user, 2026-07-07): the T agent is
   free to improve/refactor/optimize Track T sources on its own initiative —
   no ticket or approval required; improvements land under Track T's own
   gate (testmgr full green; tooling tested with quick tiers + scratch bare
   repo, never long runs).

## Authority (user-set, 2026-07-07)
- Watcher identity: writes ONLY devdocs/progress/tstate/**.
- Agent identity: MAY craft/update tickets in devdocs/progress/** (same
  authority as any track agent) — this is the deliberate difference between
  face 1 and face 2. Keep results sparse: regression signal only
  ("test xyz failed at commit abcdef"), never log dumps as tickets.

## Gate
- over a multi-day run: every NEW-RED in tstate has exactly one
  corresponding backlog ticket (no dupes, no misses), ranges narrowed to
  single SHAs, at least one regression ticket resolved by a dev track from
  the ticket alone (proves the repro quality).

## Non-goals
Fixing compiler regressions itself (files tickets for the owning track);
replacing the dev-side quick gate.
