---
prio: 60
blocked-by: [feature-track-t-watcher]
---
# Track T face 2: agentic test manager — reads tstate, crafts tickets, owns the T codebase

- **Type:** feature (test infra / agent workflow). Track T (test infra).
- **Owner:** fable-trackT (live: watcher + agent commits ongoing — see log)
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
5. **Corpus completeness (user, 2026-07-07):** absent `library_candidates/`
   trees make corpus jobs SKIP — silent coverage loss. The agent keeps its
   watcher clones complete (`tools/install_lib_candidates.sh all`); a
   SKIPping corpus job in tstate is a finding, not a green. On non-agentic
   boxes this stays a manual/user step (devdocs/dev/track-t.md).
6. **Owns the Track T codebase** long-term: testmgr.py, twatch.py, report
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

## Progress log
- **2026-07-07 (fable-trackT, session 1):**
  - Triaged tstate red test-core#261: watcher box lacked the gitignored
    tiny-regex corpus. testmgr now self-skips jobs referencing absent
    `library_candidates/<tree>` (status `skip`, pass-equivalent to twatch);
    twatch-setup checks tiny-regex-c; installer gained the missing cjson
    fetcher. (c4630097)
  - Live-daemon incident: watcher shared its clone with this dev checkout,
    ingested uncommitted edits, died on publish. Hardened twatch (per-cycle
    dirty pause, survivable cycle errors, loud death after 10 straight
    failures) and redeployed in a dedicated clone `~/trackt-watch` on borg
    with full corpus fetched. (304c0739)
  - First corpus-covered run caught a real bug: filed
    bug-crtl-printf-g-double-roundtrip (scanf floats store raw bits; %1.17g
    misrounds — verified minimal repros vs glibc). Also filed
    bug-cpp-include-not-found-diagnostic-path (Track A, diagnostic quality).
  - Perf: watcher no longer full-tiers docs/tstate-only commits (it was
    retesting its own publishes every ~5 min forever); --status applies the
    same exemption. (cc95bbf8)
- **2026-07-08 (fable-trackT, session 1 cont.):**
  - Learned-metrics scheduler in testmgr (per-box EWMA duration/RSS/cores;
    measured-mem packing, cores-sum cap, ~10x-expected hang timeouts, SLOW
    flags) and two-phase watcher (fast `native` verdict minutes after a
    push, full matrix backfills when idle, testable pushes preempt).
    (da954e2f)
  - One-stop launcher `./trackt` (status/start/stop/watch/run/setup/config/
    log/web), live.json + watch.json contracts, uncapped runs ndjson,
    optional Flask UI, deterministic stub auto-tickets (config-gated).
    (d4bf91ba)
  - Caught + fixed concurrent-gate corruption: two testmgr runs raced on
    the Makefile's fixed /tmp names (false self-host byte-diff). testmgr
    now rewrites /tmp/ into a private per-run scratch; Makefile-level
    $(TESTTMP) filed as chore-makefile-testtmp-parameterize (Track A).
  - Both regression tickets from 2026-07-07 (include-diagnostic, crtl float)
    were resolved by dev tracks from the tickets alone — face-2 gate's
    "repro quality" criterion met twice.
  - Open: LLM enrichment of stub tickets (tier 2) — config key reserved.
- **2026-07-15 (opus-trackT):**
  - **Publish-jam incident + fix.** Overnight the watcher stalled ~11h: a
    tstate `bench.tsv` append (1ecd5176) couldn't rebase onto origin because
    HUMAN commits (421bdfe7 portable-mandelbrot, c9d1c31d fpc-dialect) had
    reformatted the SAME file. `Clone.publish` aborted the rebase but LEFT
    the local commit, so every following cycle piled another unpushable
    tstate commit — 75 stranded, watcher clone 94 behind origin, nothing
    published since 07-14 18:46. No CODE lost (all commits were ancestors of
    origin); only tstate publishing stalled. Cleared the pile by resetting
    ~/trackt-watch to origin (latest-only: stale verdicts are worthless).
  - **Root fix (twatch.py):** `_pull_rebase` now returns a bool instead of
    re-raising; new `_drop_to_origin` resets the clone to the fresh origin
    tip on any failed rebase/push, so a conflicted publish DROPS this cycle
    (self-heals next cycle) instead of stranding a growing pile. Also drains
    a pre-existing pile on the next conflicting publish. Tested against a
    scratch bare repo reproducing the exact human-reformat-vs-watcher-append
    conflict (scratchpad/test_publish_conflict.py): conflict → clean at
    origin, human reformat intact, next cycle republishes cleanly.
