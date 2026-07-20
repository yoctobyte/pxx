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
  - **Publish-health visibility (b8f74a58).** The incident was invisible:
    `trackt status` showed "daemon RUNNING" above a vague "tstate DOWN" with
    no hint publishing itself was failing (DOWN is a COVERAGE verdict, not
    liveness). Added a publish-health channel: the daemon records each publish
    outcome to `.testmgr/pubhealth.json` (consecutive drops, last reason,
    commits-behind, last push); `trackt status` prints a `publish:` line
    (`⚠ BLOCKED — N drops (reason); M behind` vs `ok — last push Xago`); the
    web `/api/live` serves it and the live page shows a red banner. A daemon
    alive-but-livelocked on a conflict now shows a rising drop streak instead
    of silence. Restarted the borg watcher on the new build; the drop-fix had
    already unjammed prod (fd5b5326 published GREEN, tstate back to UP).
- **2026-07-20 (opus-trackT):** ledger flood + "watcher isn't running" —
  one root, three bugs.
  - **The flood was in the LEDGER, not the tickets.** tstate held 467 open
    regressions; the cascade suppressor had correctly filed only ONE ticket
    for the event. All 467 had `0 commit(s) in range` and 461 shared one bad
    sha across all four cross targets — a borg cross/qemu collapse recorded
    as 461 independent regressions.
  - **Root cause 1 — empty range.** `parent` in `test_sha` is the last
    TESTED sha, not the last DIFFERENT one, so the two-phase watcher (fast
    native at X, full backfill at the same X) records new_red with
    parent == sha and an empty `commits_between()`. Such an entry names no
    commit that could have caused it: unbisectable, unfalsifiable.
  - **Root cause 2 — suppression applied in the wrong place.** Cascade
    collapsing lived only in `file_stub_tickets`, so it capped tickets but
    never the ledger. Hence 1 ticket / 461 rows.
  - **Fix (ed6063f5).** `test_sha` drops empty-range sweeps (per-job red
    still lands in `st["jobs"]` and the report, so no signal is lost) and
    collapses `> CASCADE_THRESHOLD` sweeps into one `cascade@<sha>` entry
    carrying the job list. New `reg_open()` closes a cascade only once every
    job it swept is green (its synthetic key can never appear in `fixed`);
    `idle_bisect` skips cascades; TSTATE.md folds the job list; `--status`
    caps the dump at STATUS_REG_CAP (469 lines -> 14). Scratch-harness
    tested, 6 invariants (scratchpad/test_ledger.py). Purged the 467 stale
    rows in e0f60ec3 — the 461-job list survives in the cascade ticket.
  - **`--status` was reading HEAD (3a66b455).** The default CLI path
    measured coverage over `git log HEAD`, so this checkout — 226 commits
    behind — reported UP while the daemon had been stopped for hours. It is
    the exact stale-source trap `status()`'s own docstring documents, but
    only the tdir/ref callers mitigated it. Default now resolves the
    already-fetched `origin/master` (still no network) and prints how far
    behind the checkout is; both stale sources now fail toward DOWN.
  - **Root cause 3 — why it "wasn't running" (edf2291e).** The swap floor
    held admission at 233 MB free swap under a 409 MB floor while
    MemAvailable was 8.6 GB and memory PSI was flat 0.00 across
    avg10/60/300. Free swap is not a pressure signal on a desktop box: it
    fills with stale anon pages that are never handed back, so the gate
    latches shut and `admit_forced` drips the run through serially — 1011
    jobs one at a time. Scaling the floor (SWAP_FLOOR_FRAC) had treated the
    symptom; the floor now requires corroboration from PSI > PSI_QUIET or
    MemAvailable < SWAP_GATE_AVAIL, and the stall line reports all three
    numbers. PSI_ADMIT / MEM_FLOOR / PSI_KILL untouched.
  - **Tickets.** Consolidated `regression-optdiff-shard0-6` +
    `-shard5-6` into `regression-optdiff-o3-stack-frame-intrinsics`
    (61b8e58b): both named a shard rather than the failing program, and both
    point at `test/test_stack_frame_intrinsics_b270.pas` diffing -O0 vs -O3
    with rc 0 vs 0. Shard0 recurred at four shas, every sighting with 0 in
    range — a persistent differential for Track O/A, not a bisectable
    regression. NOT reconfirmed at HEAD (see below); the ticket says so.
  - **Open / handed on:** this checkout cannot build the compiler
    (`selfhost-fixedpoint`: stale seed vs post-pull sources), so no full-tier
    gate ran locally for these tooling changes and the optdiff finding could
    not be reproduced. Pre-existing and unrelated to the above, but it is
    the same failure class as the flood — a box that cannot build turns
    everything red — and it wants a Track A look.
- **2026-07-20 (opus-trackT, session 2 — watch shift):** three more fixes, one
  self-inflicted outage.
  - **Learned metrics were keyed by RECIPE POSITION (c110ad26).** `self.metrics`
    used `job.name` (`test-core#120`) — the same positional-index defect
    `twatch.job_key()` was written to fix, quoted in its own docstring
    ("inserting one test renumbers every job after it"). The ledger got the
    stable-selector treatment; the scheduler never did. So the EWMA blended
    duration/RSS/cpu across whatever different tests held a slot over time.
    Live example: `test-core#120` carried `dur=88.65s mem=6.77GB n=861` for
    `test/test_interface_mainbody_ascast_temp.pas` — a 36-line interface test
    whose binary is 36 KB. Admission then correctly refused a "6.8 GB" job
    (`avail - est_mem` under `MEM_FLOOR`), found nothing else runnable, and
    forced whole runs through serially in degraded mode — the STARVED/forcing
    storm visible all morning. Now keyed by `job.sel` via `metrics_key()`;
    legacy positional entries are DROPPED on load (a blended average cannot be
    attributed back to its sources, so it is unusable, not merely mis-keyed).
    Scale: 1163 entries dropped in the dev checkout, **1501 in the watcher**.
    Post-fix: zero STARVED/forcing events, and #120 runs concurrently again.
  - **Daemon now runs the CLONE's twatch.py (4e8674ac).** `trackt start`
    launched from the invoking checkout, so uncommitted edits in a dev tree
    decided what the watcher executed next start — code-side twin of the
    2026-07-07 dirty-clone incident. `--local-code` opts back in deliberately.
    Verified live: the running daemon's argv is now
    `/home/rene/trackt-watch/tools/twatch.py`.
  - **SELF-INFLICTED OUTAGE + fix (b50c9f03).** `daemon_pid()` tested
    `"twatch.py" in /proc/<pid>/cmdline`, which matches anything that merely
    MENTIONS the daemon. A health-check loop I started (its own command line
    contained `twatch.py --clone <clone>`) was mistaken for the daemon, so
    `trackt restart` said "daemon already running" and started nothing. The
    watcher sat DOWN while `trackt status` reported RUNNING against the
    monitor's pid — a silent outage caused by the liveness check itself.
    `is_daemon()` now parses argv and requires the real invocation shape
    (argv[0] a python, argv[1] the script, clone as a real argument). Tested
    against the live daemon and a decoy bash process embedding the string.
    Lesson for future watch shifts: a monitor that greps for a process must
    not put the pattern in its own command line.
  - **Ticket hygiene:** filed `chore-makefile-selfhost-iterate-to-convergence`
    (A), `chore-twatch-run-from-clone` (T, since resolved),
    `feature-twatch-full-tier-coverage-age` (T) in 296a0cc7.
  - **Note on a closed ticket:** `regression-test-core-test-interface-mainbody-
    ascast-temp` was resolved 2026-07-19 as "harness race" on the strength of a
    bare `Terminated` under load. The metrics-key bug is a plausible mechanism
    for those kills (same test, same box) but this is NOT established — flagged
    in c110ad26 as speculative. Revisit if they recur.
  - **CORRECTION (same day, 5db3c5b6).** The "blended metrics" diagnosis above
    was WRONG for the job it was based on. After the rekey, that job re-learned
    under the new stable key and measured `dur=80.56s mem=6.8GB` again — freshly
    sampled, no blending possible. The recipe genuinely needs it: job #120
    bundles the 36-line interface test with >340k-IR-node, 20000-symbol,
    20000-field and 12000-proc stress tests. `extract_src()` names a job after
    its FIRST source, which is the only reason 6.8 GB looked absurd. So the
    STARVED/degraded storm was the scheduler CORRECTLY refusing a job that does
    not fit — not a bug — and the purge discarded 1501 accurate entries on a
    false premise. Filed the real finding as
    `bug-test-core-oversized-job-6gb-flaky` (Track A: split the stress tests out
    of that job). The `job.sel` rekey itself still stands as a latent-bug fix
    (renumbering does blend), but it was not the cause of anything observed
    here. **Lesson: verify the mechanism before asserting it in a commit
    message — the numbers were re-measurable in one command and I did not.**
