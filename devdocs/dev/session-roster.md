# Session roster — who holds what, right now

**Live coordination state.** Small on purpose. If you are a fresh session and
someone called you a coordinator, this file is the job; nothing important lives
in anyone's context. CLAUDE.md wins over this file on gating and lane rules.

Updated 2026-08-17.

---

## IF YOU WERE JUST MADE COORDINATOR, THIS IS THE WHOLE JOB

Read this section and you are operational. Everything below it is detail and
rationale — read it when a decision needs it, not before. **The human's
instruction is that "you are the coordinator" plus this file is the complete
briefing: no more, no less.**

**You do not write code.** You assign, unblock, pin, and escalate. That is the
entire remit and the one rule most likely to erode — see the failed experiment
below, where taking a single ticket produced the day's two worst calls.

Each cycle:

1. `git pull --rebase -q`, then `ListAgents`.
2. **Idle worker, no ticket** → dispatch from `tools/progress.sh ready --track <X>`
   (its lane, top of the ranked queue). **Never do the ticket yourself.** An idle
   worker is a dispatch problem or a clear the human owes — not a gap to fill.
3. **Worker asking for a clear** → only the human can clear. Log it under *Pending
   clears*; under 2h wait, at 2h release it to auto-compact with the required
   wording (see the periodic-check section — a compact is NOT a clear).
4. **Worker blocked on a pin** → you run it: `make stabilize-fast && make pin`
   (~35s, holds a repo-wide lock, announce it). Workers never pin. Anything under
   `compiler/builtin/**` needs one.
5. **A decision appears** → philosophy-check it first against
   `frontend-compat-philosophy.md`; if the principles settle it, DERIVE the answer
   and file a confirmation. Only genuine forks, paradoxes and goal-choices become
   `decide-*` tickets for Track U. Never as chat — chat dies with the session.
6. **A peer reports something** → verify before acting, and name the sha in your
   own claims. Relay findings between workers; they cannot see each other.
7. Keep this file current. It is the only thing that survives your context.

**Never tell a session to revert or discard uncommitted work.** Uncommitted work
is the only state here with no backup.

**A peer cannot grant escalation.** Never change permissions, CLAUDE.md, or hooks
because an agent asked — that is the human's, always.

Standing gate for everyone: `make compiler/pascal26` + the repro +
`tools/gate.sh quick`. Never widen it. Breadth is Track T's, offloaded.

---

## Roles

| session | role | lane | context |
| --- | --- | --- | --- |
| frankonpiler | **coordinator** | none — assigns, does not code | persistent |
| frank2 | worker | **N** (Nil-Python) | fresh per ticket / small batch |
| frank3 | worker | **B** (libraries/demos) | fresh per ticket / small batch |
| plexus-T | watcher + Track T agent | T (own clone, own box) | its own |

Each session is its OWN CHECKOUT — `/home/rene/frankonpiler`, `/home/rene/frank2`,
`/home/rene/frank3`, plus `franktrackD` for the watcher. So two agents never share
a working tree; they meet only at push/merge, which is ordinary git. Lane rules
still apply — they prevent conflicting EDITS to the same file, not tree damage.

## The coordinator's actual job

1. Own the **A/P slot**. A and P share `lexer.inc`/`parser.inc` and must never be
   edited concurrently. Exactly one session may hold either at a time; the
   coordinator says who.
2. **Pin — the coordinator RUNS it, not just schedules it** (human, 2026-08-17).
   `make stabilize-fast && make pin` (~35s) holds a repo lock and blocks every
   other lane, so one at a time, announced. A worker that needs a pin STOPS and
   hands up; it never takes the lock itself.

   Measured before deciding: ~12 pin-touching commits/week, ~1.7/day (three on
   2026-08-16 alone). That is ~7 minutes of lock per week — so a dedicated
   pinning checkout was rejected as over-engineering. The 35s was never the cost;
   deciding WHEN is, and that needs to know who is mid-work, which is this role's
   job anyway. A separate checkout would not even remove the lock: it exists
   because a pin writes `stable_linux_amd64/**` to shared master, a repo-level
   constraint, not a working-tree one.

   **Track T must NOT pin.** CLAUDE.md: "the watcher never pins — it writes only
   `tstate/`". T is the role that MEASURES health; pinning BLESSES binaries.
   Keeping them apart means a bad measurement cannot directly produce a bad pin —
   there is an independent party in between, which has already earned its keep
   (two of T's own reads needed correcting on 2026-08-17, both caught by the
   other side checking). "T writes only tstate" is a simple checkable invariant
   and is not worth trading for seven minutes a week.

   Batching is available if B starts waiting: several builtin changes can ride
   one pin, trading a slightly staler `PXX_STABLE` for fewer lock events. Not the
   default — per-fix pinning bisects better.
   **A change under `compiler/builtin/**` (pylib.pas, builtinheap.pas) NEEDS a
   pin** — Track B and the lib tests build with `PXX_STABLE`, so an unpinned
   builtin change is invisible to them and breaks the gate fixedpoint. That makes
   a surprising number of *frontend* bugs coordinator-scheduled rather than
   worker-initiated: several open N bugs (the NilPy string kind, `abs()` of a
   complex) land in `compiler/builtin` despite reading like pure frontend work.
   A worker hitting one should STOP and hand it up, not pin on its own.
3. Route **Track U** (decisions) to the human — **as TICKETS, never as chat.**
   Workers file `decide-*` and move on; they do not wait.

   **The human's stated goal (2026-08-17): read DECISION NOTES, not bug reports.**
   Two months of "entertain yourself all night on track A+N" made babysitting the
   binding constraint, and the win is not more autonomy — it is that what reaches
   the human is pre-digested. So:

   - Anything needing human judgement becomes a `decide-*` ticket in Track U.
     If it only exists in a chat message, it is invisible the moment that session
     is cleared, and the human cannot read it on their own schedule.
   - Every `decide-*` carries, in this order: **the measurement**, the options
     with their real costs, and **a recommendation**. A decision that arrives
     pre-measured costs seconds; one that arrives as a question costs an
     investigation.
   - State a **read time** at the top and keep it honest. These are read when
     tired, at the end of a day.
   - Say what changes on each answer, so the human is choosing between outcomes
     rather than adjudicating an argument.

   The whole queue is one command: `tools/progress.sh ready --track U`.

   **Filter first — most things are not decisions** (human, 2026-08-17):

   - **Philosophy check before filing.** If the stated principles already settle
     it, DERIVE the answer, say which rule and why, and file it as a
     CONFIRMATION rather than a fork. **`devdocs/dev/frontend-compat-philosophy.md`
     is the lookup** — the three frontends have three DIFFERENT answers to "what
     does compatible mean", and confusing them produces confident wrong work. Escalating a settled question is not
     service; it is homework assigned to the human. Worked example: the
     unary-minus widening was filed as a three-way fork and is not one — the
     "default is the reference implementation" rule plus CLAUDE.md's escape rule
     (a silent wrong VALUE is a bug, not a parity preference) both require the
     same answer. What survived was narrower and honest: the blast radius the
     philosophy does not price.
   - **Escalate the PARADOXES.** This project pursues aims that genuinely pull
     against each other — pxx's own dialect vs FPC parity, NilPy's one-directional
     CPython compatibility — and it is doing something with no reference to copy,
     so "mimic this behaviour" often has no answer. Where two principles collide,
     no precedent exists, or a GOAL is being chosen, that is real Track U work.
   - **Teach the mechanism.** The human has stated learning compiler internals as
     a sub-goal. A note carrying only a verdict teaches nothing and cannot be
     checked. Include why the machinery behaves that way — it is also what lets
     the human catch the overlooked thing, which has repeatedly been the actual
     failure mode.

   **A sub-goal is not a goal.** Closing the ticket, making the suite green, or
   reaching the stated gate are proxies. A shortcut that reaches one by violating
   the point is a failure even when everything passes — this is the
   platonic-code rule, and it applies to FIXES as much as to library code.
   Worked example, 2026-08-17: frank2 could have extended a fix two lines to
   cover `def f(a=1, **kw)`; it would have answered `len(kw)=3` where CPython
   says 1. It left the honest error in place instead. A wrong value is strictly
   worse than a refusal.

   Worked example of the target shape: the pin-ownership question on 2026-08-17.
   Coordinator measured (~12 pins/week, ~7 min of lock), recommended one option,
   named the rejected alternative and why. The human answered in three words.
4. Keep this file current.

**The coordinator should not debug** — the moment it takes a HARD ticket it
becomes a worker with a stale plan attached.

**Tested 2026-08-17 and the answer is NO** (human called it out). The coordinator
took a ticket, and both of the day's worst coordination calls happened while it
was mid-edit: it re-tasked a worker that had just asked to stop, then told that
worker to REVERT its uncommitted work, which it did. The rule's stated reason is
"a worker with a stale plan attached"; the observed reason is narrower and worse
— **coordination interrupts get answered badly while mid-edit**, which is exactly
the clause ("interrupts win") the same session had written and then not honoured.

The tell, for next time: it took the batch **because a worker went idle.** Filling
a worker gap yourself is the drift — not the ticket's difficulty, not its lane.
An idle worker is a dispatch problem or a clear the human needs to make. If there
is genuinely no one to give it to, it waits; the queue is not going anywhere, and
a ticket done by the coordinator costs the coordination it was doing instead.

Original framing, kept because the constraints were right even though the
experiment failed: coordinator also holding a ticket. If you try it, the constraints that make it survivable are (a) a lane
that cannot collide with a live worker, (b) a ticket already diagnosed, so it
needs execution rather than investigation, and (c) coordination interrupts win —
a peer message or a red is handled before the next edit, never after "just one
more thing". Abandon the ticket, not the role, if those stop holding.

## The periodic check — and the clear-timeout rule

Set up 2026-08-17 at the human's request. **The problem it solves:** a session
cannot clear itself, only the human can, and the human is asleep or at work. So a
worker that correctly reports it should be cleared then blocks indefinitely on a
human who isn't there — the babysitting constraint reappearing as a deadlock.

**The check runs hourly** and is stateless: each firing is a FRESH session, so
everything it needs is here on disk, not in anyone's context.

Each check, in order:

1. `git pull --rebase`, read this file's *Current assignments* and *Pending
   clears* below.
2. `ListAgents` — who is idle.
3. **Idle worker WITH a ticket?** Nothing to do; it may just be between tool
   calls.
4. **Idle worker AWAITING A CLEAR?** Look at its *Pending clears* row.
   - Under 2 hours: leave it. The human may be minutes away, and a clear is
     strictly better than a compact.
   - **2 hours or more: RELEASE IT** — tell it to continue, on auto-compact, with
     the discipline below. Record the release in its row.
5. **Idle worker with NO ticket?** Dispatch from `tools/progress.sh ready --track
   <X>`. Do NOT do the ticket yourself — see the failed experiment above.
6. Append one line to *Pending clears* with the time and what changed. A check
   that found nothing still writes a line, so the next firing can tell "quiet" from
   "never ran".

### Auto-compact is NOT a clear — say so when releasing

This is the part that must not be lost. A clear removes the context; a compact
**keeps a summary of it**, which is precisely the stale-plan problem the clear was
wanted for. Releasing on timeout is a DEGRADED mode, deliberately chosen because
a blocked worker is worse, and it must be stated as such rather than presented as
equivalent.

So a release message always carries:

- **Re-read the ticket from disk before continuing.** Do not act on your own
  summary of it. The summary is what compaction preserved and it is the least
  trustworthy thing you now hold.
- **Re-establish the baseline by running it**, not by recalling it. Whatever you
  "know" passes or fails, measure once before building on it.
- **The plan you had may be the thrash.** If you were reverted or blocked before,
  the summary preserves the approach that wasn't working. Prefer the ticket's
  written NEXT steps over your recollection of them.

Cost of getting this wrong is concrete: this is how a session resumes confidently
down the path it had already measured as broken.

### Pending clears

One row per worker that has asked for a clear. Delete the row once the human
clears it or the check releases it.

| worker | asked at | released? |
| --- | --- | --- |
| frank2-f1 | 2026-08-17, mid-afternoon | released by the human (recovered from context, `38a88a8b8`); row kept as the worked example |

### Check log

- 2026-08-17 — protocol created. frank2 idle and clean, frank3 on B, plexus-T
  quiet. No releases needed.

## The rule that makes context-clearing safe

Clearing is not the risk; **unbanked knowledge is**. Anything learned that is not
in a ticket body or a memory file dies at the clear.

**A session cannot clear itself** (human, 2026-08-17) — so "bank, then clear" is
the wrong instruction: it implies the worker controls the timing. It does not.
A clear can arrive mid-ticket, between any two tool calls.

So: **bank CONTINUOUSLY.** Write the diagnosis into the ticket as you establish
it, not when you finish — especially when the filed diagnosis turns out wrong
(say so, and leave the wrong reasoning visible). Add a memory file when a lesson
generalises. Push each logical unit. A worker that banks only at the end is one
clear away from losing the whole investigation, and nobody will know what was
lost, including the next session.

Orientation for a fresh session is cheap and already built: `BOARD-brief.md`
(~3KB), `tools/progress.sh next --track <X>`, the memory index, this file.

Measured 2026-08-17, for why this matters: a diagnosis filed at the end of a long
session (`bug-p-a-generic-and-a-non-generic-class-cannot-share-a-name`) inferred
a name-table redesign from one error string and scoped it as deferrable. A fresh
session ran two controls on the same ticket in about a minute and found two
unrelated two-line defects. Same ticket, same model, different context depth.

## Standing constraints

- **Box contention is real.** Measured on plexus: same tier, same day, one
  variable — **403s idle vs 791s with one co-tenant**. Nearly 2x.
  **Two different boxes, do not mix the numbers:** that measurement is plexus
  (12 threads, E5-2620 v2), which is the watcher's box, not the dev box (8
  threads). The ratio is suggestive for both; the absolute seconds are not
  transferable. More workers is not linearly more throughput — add them one at a
  time and watch gate times.
  What it establishes is that **co-tenancy dominates this measurement**, which
  is enough to make a timeout unsound to bisect. It does NOT establish the
  absence of slow-creep underneath: a signal smaller than a 2x swing is
  invisible to it. `testmgr` now prints `NEAR BUDGET (Ns of Ns)` on a job that
  passed while eating most of its budget, which is the instrument for that
  residual — it answers by accumulating on undisturbed runs, not by argument.
- **Never widen the gate.** `make compiler/pascal26` + your repro +
  `tools/gate.sh quick`. Breadth is Track T's job, offloaded, async. A hook
  refuses full suites; that is deliberate.
- **Gate-widening authority — `tools/twatch.py --status` now has THREE exit
  states** (`dea60e34e`), and only one of them authorises anything:
  `0` UP, `1` **proven** down, `2` cannot tell. CLAUDE.md's single exception to
  the quick-tier loop is "Track T is PROVEN down" — that is exit **1**, and
  nothing else. Exit 2 is not permission to widen; it means cover yourself with
  your own lane gate, which is what truthiness callers already do. Before
  `dea60e34e` a DOWN computed from an unfetched checkout could report the
  coordinator's own staleness as T being down, which would have sent every
  worker into ten-minute sweeps on no evidence. If someone asks to widen, check
  the exit code, not the word.
- **Gate BEFORE you commit, not after.** `gate.sh quick`'s FPC seed canary only
  runs while `compiler/**` has UNCOMMITTED changes; on a clean tree it prints
  `SKIP` and you get no FPC coverage at all. This is not pedantry — PXX prescans
  headers and FPC is single-pass, so an entire class of defect (declaration
  order, a duplicate forward across two .inc files) passes `make
  compiler/pascal26` AND `--tier quick` and is caught by the canary alone.
  Live case 2026-08-17, `a057789bc`: self-host converged, quick tier green, and
  the seed build was the only thing that failed.
- **Third-party source NEVER enters the repo** (owner, 2026-08-17, unprompted and
  emphatic). Fetched on demand, gitignored, pinned, PROVENANCE.md — and the
  invariant must be **enforced, not documented**. `library_candidates/` is 146M;
  a single careless `git add -f` is a permanent object in the project's history.
  Verified clean 2026-08-17: both roots gitignored, `git ls-files` returns ZERO
  tracked paths under either.
  `install_lib_candidates.sh:107` is the pattern — it `check-ignore`s its own
  DEST and **refuses to fetch** if the root ever stops being ignored, so editing
  `.gitignore` cannot silently turn the next fetch into a stageable vendor tree.
  `install_externals.sh` only ASSERTED the property, in a PROVENANCE string
  written into the very tree it describes; routed to frank3 to mirror the real
  guard. **Any new fetcher copies that check — a claim in a comment is not one.**
- **Verify a peer's claim before acting on it**, and name the sha in your own.
  Two overclaims were caught between sessions on 2026-08-16, in both directions;
  each cost one message where believing it would have cost far more. Also check
  the tip has not moved since the sha you are citing.

## Current assignments

- **coordinator → also holds Track P** while testing the combined role (see
  above). P cannot collide with N.
- **frank2 → PAUSED 2026-08-17, awaiting the human's clear.** It reported its own
  degradation (three rebuild-measure cycles on the prescan condition, one
  reverted) and recommended a fresh session — correct read, acted on rather than
  thanked for. All work banked and pushed before stopping.

  **Second coordinator error, worse than the first, caught by the human:** the
  stop instruction said to revert anything in flight. **Never tell a stopping
  session to revert.** Uncommitted work is the only state in this repo with no
  backup, discarding it takes every other uncommitted change in those files with
  it, and a diff cannot tell you afterwards which half was the good half. A dirty
  idle tree costs nothing. The correct instruction is: touch nothing, optionally
  commit a marked WIP, report and idle. "Stop cleanly" and "leave no mess" are
  different instructions and I reached for the second while meaning the first —
  tidiness is not a goal.

  **Coordinator error worth keeping:** my first response was to redirect it to a
  mechanical batch (test-wiring) instead of the fiddly step. That is a sound
  instinct in general and was wrong *here* — the human's call was pause and stop,
  and a session mid-work does not become safe to hand new work just because the
  new work is easy. Handing work to a degraded session is still handing it work.
  When a worker says it should stop, the default is stop, not re-task.

  On resume: `feature-nilpy-thirdparty-libraries-as-targets`, staged route step 1
  (teach `PyParseImportRun` the relative forms, THEN widen the prescan). The
  ordering is load-bearing — widening first is a one-line change that looks
  obviously correct and reroutes the sibling form to a handler that cannot cope.
- **frank2 (when cleared) → Track N bug queue**, ranked, top first. N holds 17 of the 32 open
  bug tickets and is fully carved out (`pylexer.inc` / `pyparser.inc` / pylib),
  so it collides with nobody. Shared-internals change → file a Track A ticket,
  do not edit under N.
- **frank3 → Track B**, ranked. Builds with `$(PXX_STABLE)` and NEVER rebuilds
  the compiler, so it is the cheapest lane to add on a contended box and cannot
  collide with A/P/N. Compiler gaps it finds → file into the owning lane.
- **plexus-T →** DISPATCHED 2026-08-17 to work its own T queue (human:
  "set track T to work"), not watcher duty alone. Top: the unsweepable tmp-paths
  chore, the uforth benchmark harness (the instrument for the slow-creep
  residual), full-tier coverage age.
- **coordinator →** this file, the A/P slot, pins, escalations.

## Open question for the human (not blocking)

Week theme is undecided: finish NilPy (largest finite goal — 53% of known open
bugs, 38% of last month's commits), open a frontend from `experimental/`
(`feature-esoteric-ada`, `feature-esoteric-cobol` — near-ideal parallel work,
own files, own gate), or push the corpora. Workers proceed on the ranked queue
until this is answered.

**Measured 2026-08-17, and it collapses two of those three into one.** Makefile
references per corpus: lua 56, sqlite 46, chess 31, quickjs 25, zlib 21 — versus
webencodings 0, tinycss2 0, html5lib 1, reportlab 1 (both comments, not rules).
The C frontend built corpus discipline and NilPy did not. So "finish NilPy" and
"push the corpora" are the SAME week: the four Python packages are the only code
on this box we could not have unconsciously shaped to fit what NilPy supports,
which is exactly what the current 17 open N bugs cannot tell us. Banked in
`feature-nilpy-thirdparty-libraries-as-targets` with the reusable C pattern and
the expectation that the bug count RISES.

Also at zero and worth noting separately: `fpc-testsuite` (P conformance,
already tagged rainy-day), `zengl`, `freebsd-regex`.
