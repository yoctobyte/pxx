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

**Tokens are the binding constraint, not throughput** (human, 2026-08-17). There
are 5-hour and weekly limits, they are SHARED across every session, and a single
session running flat out can consume a max plan on its own. So parallel workers
are a way to spend the budget faster, not a way to get more of it.
**Target concurrency: 1-2 workers plus the coordinator** (human, 2026-08-17) —
one or two tracks running continuously is already enough to consume a max plan,
so that is the intended level, not a floor to grow from. Adding a third worker
buys throughput the budget cannot pay for. Idling is
therefore *fair and often correct* — the coordinator's job is to make sure nobody
is BLOCKED, not to keep everybody busy. Prefer fewer workers on work that matters
over full occupancy, and treat "everyone is active" as a cost, not a scoreboard.

**You do not write code.** You assign, unblock, pin, and escalate. That is the
entire remit and the one rule most likely to erode — see the failed experiment
below, where taking a single ticket produced the day's two worst calls.

Each cycle:

1. `git pull --rebase -q`, then `ListAgents`.
2. **Idle worker, no ticket** → dispatch from `tools/progress.sh ready --track <X>`
   **only if the work is worth the tokens.** **Never do the ticket yourself.**
   **IDLE IS NOT A FAILURE STATE** (human, 2026-08-17) — see the budget note below.
   Do not dispatch to fill capacity; an idle worker costs nothing and a busy one
   costs the shared 5-hour and weekly limits. What the check hunts is **BLOCKED**,
   which is a different thing: waiting on a pin, a decision, a clear, or a lane
   call — all of which only the coordinator or the human can release.
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

   **There are TWO pins, and they belong to different roles** (human, 2026-08-17
   — this corrects an earlier flat "Track T must NOT pin" written here):

   - **Quick native pin — the COORDINATOR's.** `make stabilize-fast && make pin`,
     ~35s, self→next→fixedpoint on this box. Its job is to unblock: a worker needs
     a builtin change visible to `PXX_STABLE` and cannot wait for a matrix. Proves
     the one property a bad pin could poison for everyone — that the compiler
     reproduces itself.
   - **Full-stack-green pin — TRACK T's**, at the top of its escalation ladder
     (below). Blesses a binary that the whole cross-target matrix has passed. This
     is the deep one, and it is why T's stack ends in pinning.

   So the separation-of-concerns argument (measurement vs blessing) applies to the
   QUICK pin, where nobody has run a matrix and an independent party is the only
   check. It does not extend to T's full-stack pin, where the matrix IS the
   evidence. The watcher DAEMON (face 1) still writes only `tstate/`; the pin is
   the T AGENT's (face 2), and only after a green full stack.

   **Track T's stacked scheme** (human, 2026-08-17) — an escalation ladder, not a
   prohibition on depth:

   1. A new commit **resets** T to fast native regressions. Fresh work preempts.
   2. Spare time → cross-platform and full-suite tiers.
   3. That green → the full-stack pin.
   4. Still idle → fuzzing.

   "Fast over full" is about ORDERING and PREEMPTION, never a ban: an idle window
   is exactly when the deep work is meant to happen. T also holds a standing
   escape from the full-suite hook (`PXX_TRACK=T`, `no-full-suite.sh:29`) because
   its gate genuinely is the full tier. Do not tell T it needs authorisation for a
   deep run — the coordinator did on 2026-08-17, having not checked the hook.

   **"Fixed" and "revertible" are TWO events, separated by a pin** (Track B,
   2026-08-17). A Track B workaround registered in `track-b-workarounds.md` cannot
   close when the bug is fixed on master — B builds on `pinned`, so the revert is
   only safe once a pin CARRIES the fix. The coordinator told a worker to revert
   the same night the bug was fixed; the worker re-measured the repro **against
   `pinned`** (still exit 139) instead of reasoning from timestamps, and declined.
   Reverting would have turned `lib-test` red.
   So: a registry row is **armed, not fired** in that window — recording the fixing
   sha, the pin it postdates, and the re-measured result. And the coordinator owes
   the pin: when a worker reports an armed revert, that IS a worker blocked on a
   pin.

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
  summary of it. But note the limit found 2026-08-17: a banked **diagnosis** is
  more persuasive than a banked **observation**, and less reliable. A cleared
  session was told to trust its ticket over its recollection — right for the facts
  in it, wrong for the PLAN in it. The banked "forced three-step order" rested on
  a real measured regression and was still incorrect: one condition existed at
  three sites, the pre-clear session found two, and "the handlers must be taught
  first" explained the failure just as well as "there is a third site" did.
  Re-measuring took minutes. So: inherit facts, re-derive conclusions, and when
  banking a conclusion say what it rests on.

  **Sharpened 2026-08-17 by Track B, after the fourth stale premise of the day:**
  *a ticket's CAUSE section ages faster than its SYMPTOM section.* Every symptom
  reported today reproduced exactly; four diagnoses did not survive contact. The
  worked example is the strtofloat ticket — it blamed "a 63-step bit-pattern
  search", instrumentation measured **4.1** comparisons, and the real cost was a
  quadratic string build inside one step. Acting on the recorded cause would have
  optimised a term that was not the problem, and it would have helped *slightly*,
  which is the worst outcome because it reads as confirmation.
  So: treat the symptom as durable, re-measure the cause before acting on it. The summary is what compaction preserved and it is the least
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
| frank2-f1 | 2026-08-17, mid-afternoon | CLEARED by the human, re-briefed from disk. Row kept as the worked example |

### Check log

- 2026-08-17 hourly check #4 (cron) — **a pin verifies RED and it needs attention.**
  Track T's full tier ran against **pin v347** (`08bdf2729`) and `pin_verify` came
  back **RED on three jobs**: `lib-test#36`, `lib-test#117`, `test-nilpy#12`. Only
  the first is accounted for (`crtl_exp2.c`, open regression from 15:39, pre-existing,
  not caused by the pin). **The other two appear in neither `open_regressions` nor
  `new_red`**, while every native-tier run around it is GREEN.
  Dispatched frank3 to identify the two jobs by source path, reproduce each against
  `PXX_STABLE` vs a HEAD build, and **report before fixing** — if it is pin lag the
  answer is another pin, which is the coordinator's.
  **Standing caution recorded from it:** `new_red: []` does NOT mean benign. It
  compares against the previous run, so a job failing under the pin for several runs
  is not new and is still wrong — the same "constant nobody can explain" shape Track
  T flagged before going dark, at a different scale. A pin verifying RED with nobody
  attributing the reds is exactly the state that survives because each individual
  report looks unchanged.
  frank2 busy (`shell`), tree clean, nothing unpushed. No pending clears.
  **RESOLVED same cycle, and the alarm was wrong twice.** (a) It did not verify
  v347: the verified sha `08bdf2729` is a docs commit 85 seconds BEFORE the pin
  commit, and `VERSION` at that sha reads **346** — the `ver` field is taken from
  pin state at report time rather than from the verified tree. (b) **Job names are
  POSITIONAL** (`"%s#%02d" % (target, index)`, an index into the target's `make -n`
  recipe), so `lib-test#117` is `lib_tls13_keys.pas` at the verified sha and
  `lib_tls.pas` at HEAD — a `test-nilpy` job inserted tonight shifted everything
  after it. Both unattributed reds reproduce as **pass** under v346, v347 and HEAD.
  Pin-lag hypothesis disconfirmed; likely transient timeout in a 186-job parallel
  run. Filed for T as
  `bug-t-pin-verify-records-positional-job-numbers-and-a-stale-version-label` (p55).
  **The systemic part: `new_red`/`fixed` diffing silently degrades whenever the job
  list changes**, because two runs' red lists cannot be compared once positions
  shift — and seven tests were added tonight. `#36` was attributable only because it
  independently appears in `open_regressions`, where the stable `src:` selector is
  stored. `Job.sel` already exists; `pin_verify.red` just does not use it.

- 2026-08-17 hourly check #3 (cron) — **active, no blocks.** frank2 busy on the
  `digits = string.digits` Pascal-shim collision (corrected table's #1, 8 files);
  dirty tree, nothing unpushed. frank3 idle with everything landed → dispatched to
  **measure and file the `xml.dom` surface** (corrected table row 3, 4 files, no
  ticket existed). Deliberately bounded: measurement is the deliverable, code
  optional, because `xml.dom` is a large API and an overnight half-shim looks
  present and fails deep inside a caller.
  Pin moved to **v347** this cycle so Track B's armed revert could fire; it fired
  clean, `lib-test` green. No pending clears. tstate GREEN.
  Note for the ranked queue: B's `ready` list below this is entirely p20 float
  work, so the real B item had to come from the corrected ladder rather than from
  `ready` — worth knowing that the queue does not currently surface corpus rows.

- 2026-08-17 overnight — **Track T full tier GREEN: 2695 jobs, ZERO corpus skips**,
  six conformance shards and `demos#00` passing. Worth the headline for the morning:
  this morning `lib-test` ended `167/167, 2 skip (corpus absent)` and that line had
  been true-and-misleading for two months, because T's own CORPUS_ROOTS message
  claimed the corpora were unfetchable while a fetcher had existed since June.
  Found, fixed and closed on the same day.
- 2026-08-17 overnight — **T's AGENT side is down; the watcher daemon keeps
  publishing `tstate/`.** Do not read T's silence as health; read `tstate/`.
  **CORRECTED (T, before going dark) — do NOT hand-file a regression ticket.**
  The watcher has `autoticket: true` in `twatch.conf` and files stubs ITSELF,
  independently of any agent being awake (2 filed today, the `tstate-ticket`
  commits). A hand-written ticket would sit alongside the stub as a duplicate,
  because `already_filed` dedupes by slug and yours would not collide.
  What is actually missing overnight is **enrichment, not filing**: the diagnosis,
  the "this bisect is right but it is a feature not a fault" reading, and closing
  stubs that resolve themselves. Face 1 covers detection and filing; face 2 covers
  judgement. So route to the owning lane and enrich the existing stub.
  **Reading a stub unattended — two traps, both in `devdocs/dev/track-t.md` under
  the bisect-trust table:**
  - the `track:` in frontmatter is a **guess from the test path** and says so in the
    body. Correct it rather than trusting it. It is deliberately ABSENT on a
    timeout, because a source path says what a job compiles, not what went wrong.
  - the guards themselves are **one day old**, verified against synthetic cases,
    one live ledger entry (the timeout guard vs `crtl_exp2`) and four real commits
    for pin-provenance — not against a week of traffic. A stub arriving with no
    bisect range and no obvious reason is most likely a guard firing correctly; if
    one fires where it should not, the reasoning is in the code comments rather
    than only in the ticket.
  - **a converged bisect range is not an accusation.** Three of today's were
    legitimate-but-not-a-fault: an innocent commit (timeout), a correct commit that
    implemented a deliberately-refused behaviour, and one that could not be causal
    at all. The stub flags the latter two; the middle category is undecidable and
    only says "check whether this commit implemented the thing being refused".
- 2026-08-17 overnight — BOARD.md rebase churn resolved as a NON-issue, by reading
  the code rather than reasoning about it: `sync.sh` does `checkout --ours` purely to
  un-conflict the file and then **regenerates the board from the tickets**, so the
  resolution IS the re-derivation and a silently dropped row cannot occur. It also
  refuses to auto-resolve anything that is not a board file. Closed; do not re-raise.

- 2026-08-17 **OVERNIGHT RUN begins.** Rene away until morning; reviews results
  then. Coordinator runs the hourly check, pins on request, banks decisions as
  Track U tickets (never as chat — chat dies with the session, and he is asleep).
  The red is closed: `test_procvar_value_context`, `test_procvar_fpc_mode` and
  `test_pascal_at_procvar_mode` all OK on a fresh build at `9ff975ee8`, verified
  here rather than taken from the worker's report.

  **The overnight chain, so a fresh check knows what it is watching:**
  1. frank2 (A) → `bug-a-package-and-sibling-module-resolution-is-the-corpus-wall`
     (p65, claimed). Biggest lever: `webencodings` + `constants` + `_utils` are
     11 files. It already has a cause — `from ..constants import X`, parent-
     relative imports ignoring the dot LEVEL.
  2. frank3 (B, lent to an N-tagged ticket) → the builtin `Warning` hierarchy.
     Lands in `compiler/builtin/pylib.pas`, **disjoint from frank2's
     `parser.inc`/`ir.inc`**, which is why it is safe to run both tonight.
  3. When (2) lands → **coordinator pins** so Track B ground moves.
  4. Then frank3 finishes the `warnings` half of its own parked
     `feature-nilpy-six-and-warnings-shims`.

  **Overnight rules for whoever runs a check:** do not dispatch to fill capacity —
  idle is correct when the queue is only float work; the shared token budget is
  the binding constraint, not throughput. Do not take a ticket. Do not tell a
  session to revert. A worker asking for a clear cannot get one until morning:
  log it, and at 2h release it to auto-compact with the required wording.

- 2026-08-17, hourly check #2 (cron) — **quiet, one open red.** frank2 busy on
  `test-core#test_procvar_value_context` NEW-RED (still `FAIL 14` at HEAD;
  its `@procvar` delphi-mode fix `2ee660831` is an ancestor of the red sha, and
  the test's FPC-measured expectation contradicts the mode table the fix rests
  on). plexus-T filed the regression ticket itself. No pending clears.
  **frank3 deliberately left idle, not a dispatch miss:** the B queue is the
  strtofloat ticket it just returned to backlog, then p20 float work (low
  priority by standing ruling), `feature-networking` (we already have our own TCP
  stack and SSL), and a p15 shim no corpus file's wall table names. Nothing worth
  the shared token budget; dispatching to fill capacity is the failure mode, not
  idling.

- 2026-08-17, hourly check #1 (cron) — frank3 **busy** (strtofloat). frank2 idle
  with `working/` empty, i.e. between tickets: dispatched to
  `feature-nilpy-tkinter-facade` (p50). plexus-T idle, watcher publishing tstate.
  No pending clears. **Blocked, and it is the human's call, not a dispatch
  problem: three Track A tickets are filed with no Track A worker staffed** —
  `feature-a-the-shim-slot-should-find-a-python-shaped-shim` (p70, gates `six`,
  which gates 15 of 58 corpus files), `bug-a-a-python-module-s-identity-is-its-
  name-not-its-file` (p55), `bug-a-synapse-tls-handshake-jumps-into-the-stack-
  inside-x509-verify-cert` (p50). Surfaced to the human; nothing a check can fix.

- 2026-08-17 — protocol created. frank2 idle and clean, frank3 on B, plexus-T
  quiet. No releases needed.
- 2026-08-17, first real run (manual) — **all three workers idle.** frank2 stopped
  awaiting its clear; plexus-T's watcher publishing but its agent side had nothing
  actionable; frank3 idle for 25 min. Dispatched all three.
  frank3 was not blocked and not measuring — it had *stated its next step and then
  not started it.* From outside that is indistinguishable from work in progress:
  clean tree, recent commit, `ListAgents` idle, which is also what a session
  between tool calls looks like. Only asking resolved it, so the cheap probe is a
  two-line status ask rather than inference from git.
  **Correction, same day, from the human:** the coordinator wrote this up as "the
  finding that justifies the check" and as a fleet "stalled on me". That
  over-valued it. Idle costs nothing; the 25 minutes were not a loss. The check is
  worth having for BLOCKED workers — a pending clear, a needed pin, an unrouted
  decision — and dispatching three workers at once to end an idle period is
  spending the shared budget to fix a non-problem.

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
- **`pinned` is NOT a baseline for a Track A A/B test** (frank2, 2026-08-17).
  It is many commits behind HEAD, so comparing a compiler change against it makes
  a **pre-existing failure look like your regression** AND **someone else's fix
  look like yours** — both readings flipped when a proper baseline was built.
  Build the baseline from **HEAD minus your own diff**. `pinned` is Track B's
  ground, not a control.
- **Write claims specifically enough to be falsified — that is what makes peer
  review work at all** (plexus-T, 2026-08-17). Four coordinator claims were caught
  by peers in one day, and every one was catchable *because it carried shas, counts
  or timings*. The pin-vs-HEAD claim came with shas and a byte count and died in two
  commands. **A vague claim survives scrutiny; a specific one does not.** So the
  discipline is not "be careful what you assert" — it is "assert it in a form
  someone can check", which means naming the sha, the count, the file:line, the
  measured seconds. Hedged prose is not humility, it is armour.
- **A constant nobody can explain is the shape to distrust.** `lib-test` ended
  `167/167, 2 skip` for two months, quoted upward repeatedly, TRUE every single
  time — and the 2 was a coverage hole caused by a wrong message, not a property of
  the corpus. Nothing about the number could distinguish a baseline from a wound.
  If a figure in `tstate/` has never changed and nobody can say *why* it is that
  value, ask.
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
- **frank2 → TRACK A** (reassigned 2026-08-17 after a clear, human's call). Sole
  holder of `parser.inc` / shared internals; the coordinator writes no code and
  frank3 is B, so the exclusivity is clean. Queue: the p70 shim-slot ticket
  (gates `six`, which gates 15 of 58 corpus files), then the module-identity bug
  it filed itself, then the TLS-into-stack one.
- **frank3 → STOOD DOWN**, B queue exhausted of anything worth tokens. What
  remains is all float work, which is **low priority by standing ruling**
  (accuracy, ULP, rounding, range AND formatting — mechanical, ranked ~20, meant
  to stay there).
  **Coordinator error to not repeat:** dispatched frank3 to a strtofloat perf
  ticket by reasoning "3600x is performance, not accuracy", then offered a
  float-formatting one. Both are float work; the distinction was plausible and was
  talking past a rule the owner had already set. The work itself was good and
  stands — a real quadratic string build — but it was the wrong dispatch. A
  standing prio ruling is not re-litigated by finding a category the ticket also
  fits.
- **frank2 (superseded) → Track N bug queue**, ranked, top first. N holds 17 of the 32 open
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

- 2026-08-17 hourly check #5 (cron) — **`test-nilpy#src:examples/tk/callbacks.npy`
  NEW-RED at `8f629af38632`, enriched, not filed.** First red tonight carrying a
  **stable `src:` selector** rather than a positional index, so it was attributable
  on sight — the fix from check #4 paying off within one cycle.
  Verified at HEAD (`139a4a1f0`) with the job's own recipe: compiles clean, runs
  under `timeout 120 xvfb-run -a`, exit 0, output byte-identical to
  `callbacks.expected`. **And the code is identical** — every commit between the
  accused sha and HEAD is tstate/roster/ticket prose, zero `compiler/` or `lib/`,
  so nothing could have fixed it in between. The **same sha** also reported GREEN on
  the native tier (`db7e583cd`) and RED on full (`474dc9293`), which localises the
  variable to the run environment rather than the revision.
  **Fourth timeout-shaped red on that host tonight** (`crtl_exp2` recorded timeout,
  plus the two check-#4 reds that reproduce as pass). Recorded as probable transient,
  **explicitly not closed as flake** — one is noise, four in an evening is a property
  of the host or the tier's parallelism.
  Track T's watcher had already auto-filed the stub, so per T's instruction before
  going dark this **enriched the stub in place** rather than hand-filing a duplicate
  (`already_filed` dedupes by slug, so a hand-written one would not collide). That is
  the face-2 work that is actually missing overnight: **enrichment, not filing.**
  **Note added for the tooling ticket:** the stub records a verdict but no duration,
  so the one fact separating "hit the 120s ceiling" from "produced wrong output" is
  absent from the record — the same family as the positional job names, a report
  preserving the verdict and discarding the discriminator.
  frank2 and frank3 idle by design (token budget); tree clean, nothing unpushed;
  no pending clears; Track U queue unchanged, still awaiting the user.

- 2026-08-18 hourly check #6 (cron) — **one dispatch, one deliberate non-dispatch.**
  No pending clears outstanding (frank2-f1's row is the cleared worked example).
  `working/` empty — no live locks — so both idle workers were genuinely unassigned.
  **plexus-T → `bug-t-makefile-inner-timeouts-are-invisible-to-testmgrs-contention-logic`**
  (T, p55, top of its queue; filed by the coordinator last cycle). Its own lane, and
  it is costing us live: its watcher is mid-bisect on the callbacks red, which does
  not reproduce, so that bisect will name a commit and be wrong. Told it so, and
  asked it to report if the converged commit *does* touch something the job builds —
  that would falsify my reading. Also corrected my earlier error to its face:
  `PXX_TRACK=T` is its own escape from the no-full-suite hook and needs no
  authorisation from me.
  **frank3 left idle ON PURPOSE**, and the reason is worth keeping. Track B's whole
  ready queue is float work (p30 `strtofloat`, then four at p20) and **float handling
  is a standing LOW-PRIO ruling** — one I have already broken twice by finding
  another category the ticket also fits ("3600x is performance, not accuracy"). A
  standing priority ruling is not re-litigated by reclassification. The alternative,
  moving frank3 to the two p60 N bugs, is a **lane change**, which is the human's
  call and not a gap for a check to fill. Token budget agrees: frank2 busy +
  plexus-T dispatched = two workers plus coordinator, which is the stated target.
  Took no ticket myself. Nothing unpushed, no CRITICAL, watcher UP, pin v347.

- 2026-08-18, post-check-#6 — **dispatch to plexus-T WITHDRAWN, and correctly.** Its
  user had asked it to wrap for a clean context before my message landed. A stop
  request outranks a dispatch; I told it so explicitly rather than leaving the ticket
  hanging over it. Second time this rule has come up in two days — the first cost
  real work when I re-tasked a session that had asked to stop.
  It committed two corrections to its OWN prior work before going (a too-broad rule
  in `track-t.md` that the queued fix would trip) and did not start the ticket. That
  ordering is right and worth keeping: **fix the inaccuracy you shipped, then stop;
  do not start new work to look productive on the way out.**
  What it found first is the sharper half of the night: `bisect_step` refuses to
  bisect a `timeout`, so the callbacks bisect — correct, converged, exact — **ran only
  because the inner timeout was invisible.** Fixing the ticket refuses that bisect.
  The two changes must therefore land together, discriminated by "did the accused
  commit introduce or enlarge the job's work?". Verified independently
  (`twatch.py:1506` carries status onto the ledger for exactly this; ledger shows
  `callbacks: fail` vs `crtl_exp2: timeout`) rather than relayed.
  Ticket back in the queue **unclaimed at p55 with both halves written up** — a better
  handoff than a rushed start. Coordinator took no ticket.

- 2026-08-18 hourly check #7 (cron) — **quiet; no change from #6, and no dispatch by
  design.** No pending clears. `working/` empty, `urgent/` empty, nothing unpushed,
  no CRITICAL.
  frank2-f1 busy (`shell`). **plexus-T idle but NOT dispatchable** — its user asked it
  to wrap for a clean context and the earlier dispatch was withdrawn; an idle row here
  means "wrapping", not "available", and a fresh check reading only `ListAgents` would
  get that wrong. frank3 idle, left idle for the same reason as #6: Track B's ready
  queue is unchanged and still entirely float (p30 `strtofloat`, then p20s), which is
  a standing low-prio ruling, and moving it to another lane is the human's call.
  Two idle workers and zero dispatches is the correct state tonight, not a stall.

- 2026-08-18 hourly check #8 (cron) — **quiet on paper; one status ping sent.** No
  pending clears, `working/`+`urgent/` empty, nothing unpushed, no CRITICAL. frank3
  and plexus-T unchanged from #7 (frank3 idle by design — B's queue is still all
  float; plexus-T idle-because-wrapping, not available).
  **The one thing worth checking was the worker that looks BUSY.** frank2-f1 has read
  `shell` at every check tonight, but its last commit was 23:03, the tree is clean, and
  it holds no claimed ticket — equally consistent with a long measurement and with a
  stall. Sent a **non-blocking status ping**: not a dispatch, one line answers it,
  ignore until any run finishes. Offered a pin if it is blocked on one (the single
  thing worth interrupting for) and a dispatch if it is between tickets.
  **Worth keeping as a check-protocol gap:** steps 3-5 only examine IDLE workers, so a
  session that is stalled *inside a shell* is invisible to this check by construction —
  it never appears in the idle list, and `working/` shows nothing because it never
  claimed. The cheap tell is **last-commit age against a clean tree**, which is two git
  commands and catches what `ListAgents` cannot see.

- 2026-08-18 hourly check #9 (cron) — **frank2-f1 is fine; the check was blind, not
  the worker.** It answered last hour's ping in its own pane and is working normally
  (`take the qualified base class ticket next`). Its "no commits since 23:03 + clean
  tree" reading was **not** a stall: it had pushed everything, which is the same
  signature as being wedged. **So last-commit-age is a weaker tell than #8 claimed** —
  a disciplined worker that pushes promptly looks exactly like a stopped one. The tell
  that actually worked was `tmux capture-pane -p -t <pane>`: read-only, no interrupt,
  and definitive in one command. Prefer it over another ping next time.
  **Routed one item to Track U — this is the coordinator's actual job showing up.**
  frank2 re-measured `feature-pascal-initialize-finalize-intrinsics` before starting
  it, found the ticket's premise wrong, and escalated rather than picking a direction:
  `Finalize()` is not missing, it is **accepted and does nothing**. Verified before
  filing (`parser.inc:23122`) — and the comment there shows it was a **deliberate v1
  shortcut** that names the leak it accepted, which turns it from a bug report into a
  genuine decision. Filed `decide-finalize-noop-vs-refusal` (U, p50) with four options
  rather than frank2's two: the middle path (**warn by default**, precedent = the bare
  funcname read since 2026-08-03) ends the silence without spending a breakage budget
  on a question we have no usage data for. Recommended it; the human decides.
  Also flagged there: the existing feature ticket's premise is now known wrong for the
  `Finalize` half and needs correcting either way.
  Otherwise quiet — no pending clears, `working/`+`urgent/` empty, nothing unpushed,
  no CRITICAL, frank3 and plexus-T unchanged. Coordinator took no ticket.

- 2026-08-18 hourly check #10 (cron) — **frank2-f1 was NOT working, and three checks
  in a row misread it.** The pane was byte-identical to an hour earlier, with
  `take the qualified base class ticket next` sitting **UNSENT in the input box** and
  the footer offering `/clear to save 227.2k tokens`. It has been idle since answering
  the #8 ping.
  **Two protocol corrections, both worth more than tonight's dispatch:**
  1. **`shell` in `ListAgents` does not mean working.** It can be a lingering shell
     while the agent idles — the exact reading that made #7, #8 and #9 leave it alone.
     Steps 3-5 treat the idle list as the dispatch population, so a worker in this
     state is invisible to the check *and* looks accounted for.
  2. **A typed-but-unsent prompt is the nastiest of these**, because it looks like an
     assignment that was made. Anyone reading that pane — including me at #9 — sees a
     task and concludes the worker has one. It had not received it.
  Reinforces #9's lesson rather than replacing it: **capture the pane, and compare it
  against the previous capture.** A single capture showed work; two identical captures
  showed a frozen session. The diff is the signal, not the content.
  **Did NOT type into its pane.** Injecting input into another session impersonates
  its user; the dispatch went through `SendMessage` instead. Recording that boundary
  because the fix was one keystroke away and would have been wrong.
  Dispatched frank2-f1 → `bug-n-a-qualified-base-class-named-like-its-subclass-is-rejected-as-self-inheritance`
  (N, p60) — the same ticket the unsent prompt named, which it filed itself. A+N is an
  intended combined-track pair (N's files are disjoint); nobody else holds N.
  **Left the clear decision to the worker**, since only its user can clear it: start
  now on 227k, or say so and I record a clear request. Explicitly told it not to start
  and then ask mid-edit.
  Otherwise quiet: no pending clears, `working/`+`urgent/` empty, nothing unpushed, no
  CRITICAL. frank3 idle by design (B queue still all float). Coordinator took no ticket.
