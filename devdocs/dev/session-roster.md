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

- 2026-08-18 hourly check #11 (cron) — **the #10 dispatch paid off, and the unsent-prompt
  pattern RECURRED.** frank2-f1 took the qualified-base-class bug and landed it at 04:45
  (`fix(N): a .py module's class no longer fills the program's same-named row`), with the
  new test wired into **both** `test-nilpy` and `test-core` so the quick tier covers it
  rather than only the nilpy suite — the right instinct, unprompted. The five html5lib
  filters that reported self-inheritance now stop further along.
  Then it went idle again with a **second unsent prompt** in its box (`take the module
  locals cap ticket next`) while reporting "between tickets again, nothing blocked".
  **So this is systematic, not a one-off** — something types into that pane without
  submitting, and the worker never receives it. Two consequences for the protocol:
  (a) it will keep looking assigned to anyone reading the pane, and (b) every dispatch
  to it must go through `SendMessage`. Still did not type into the pane.
  Dispatched frank2-f1 → `bug-n-the-module-locals-cap-hides-a-compiler-stack-overflow`
  (N, p50), the ticket that prompt names and the exact wall its own fix exposed.
  **Emphasised the trap in it**, because it is the kind a green corpus number invites:
  raising `PY_MAX_LOCALS` alone is NOT the fix — with the cap raised two html5lib files
  SEGFAULT the compiler (exit 139, no diagnostic), and `ulimit -s unlimited` turns the
  crash back into a diagnostic, so the cap has been masking a stack overflow. Raising it
  first converts a clean refusal into a silent crash. Told it to keep the ordering
  constraint it recorded itself, and that if the overflow lives in shared core it is a
  Track A ticket even when self-resolved.
  Clear decision left with the worker again (only its user can clear). Otherwise quiet:
  no pending clears, `working/`+`urgent/` empty, nothing unpushed, no CRITICAL, frank3
  idle by design. Coordinator took no ticket.

- 2026-08-18 ~06:00 (monitor event, between checks) — **first REAL red of the night,
  and it is native-tier.** `ce57db4cd` ("fix(A): lower a statement list iteratively")
  RED on native with three NEW-REDs: `test_nested_class_type_b348.pas`,
  `test_set_literal_element_types.pas`, `test_set_runtime.pas`.
  **Attribution is one commit wide and clean** — `e0f6748717e6` GREEN on native,
  `ce57db4cd` RED, nothing else between. Distinguished from the night's four
  timeout-shaped reds on the two facts that matter: native is the FAST tier (no
  contention story) and three related Pascal tests failing together is a behaviour
  signal, not a duration one. The commit touches `ir.inc` (+51) and `defs.inc` (+23)
  — shared core.
  Routed to frank2-f1, which owns the commit and was still active: reproduce one,
  decide fix-forward vs revert and say which, push promptly. Left the choice with it
  rather than mandating a revert — CLAUDE.md's revert rule applies, but it can see the
  cause faster than I can. Stated explicitly that this concerns a **committed, pushed**
  change and asks nothing about its dirty tree, since that distinction cost real work
  yesterday.
  **No PushNotification.** The human set up overnight autonomy and will evaluate at
  wake; a worker is on it with a one-commit range, so waking them adds nothing they
  could do better. Recorded in the digest instead.
  Worth keeping: the regressing commit is the **stack-overflow half** of
  `bug-n-the-module-locals-cap-hides-a-compiler-stack-overflow` — the half that was
  correct to do first. So that ticket's ordering constraint is two-way, not one-way.

- 2026-08-18 ~06:12 (human wake, out of band) — **the box REBOOTED at ~06:09; every
  session died.** `uptime` said 3 minutes at 06:12 and the last commit on master is
  `d90bc323a` at 06:03, so the window is 06:03-06:09. `ListAgents` reports nothing
  reachable, no `twatch`/`testmgr` process is running, and only this coordinator pane
  exists. **Track T is therefore DOWN by process, not by report** — its own `--status`
  still reads UP because that reads the published `tstate/`, which is simply frozen at
  `61e2448bac6d`. Restarting the watcher in `franktrackD` is the first thing to do.
  **The native RED is still open at HEAD and is REPRODUCED**: all three of
  `test_nested_class_type_b348`, `test_set_literal_element_types`, `test_set_runtime`
  fail with `invalid optional IR node reference in block first` against a fixedpoint
  build at `d90bc323a`.
  **But frank2-f1 had already fixed it before the power went** — `/home/rene/frank2`
  holds one uncommitted file, `compiler/ir.inc`, with the diagnosis written into the
  comment: the iterative statement-list fold lost the `seqCur >= 0` test that the
  recursive version got for free at the top of `IRLowerAST`, so an empty `-1` tail read
  `ASTKind[-1]` and folded an `IR_BLOCK` over garbage. Set literals are where `-1` tails
  are common, which is why those tests went first. Two `PXXDBG a.seq` probes ride along
  in the same diff.
  **That work is uncommitted and is the only copy** — it must not be duplicated from
  here and must not be discarded. Landing it belongs to frank2-f1, which also still
  holds `bug-n-the-module-locals-cap-hides-a-compiler-stack-overflow` in `working/`.
  Left with the human at wake.

- 2026-08-18 ~06:25 — **CORRECTION to the entry above: Track T is UP, and was never
  down.** I checked `pgrep twatch` on THIS box and read the empty result as the daemon
  being dead. **plexus is a different machine** — the roster's own Roles table says so
  ("own clone, own box"), and the reboot here could not have touched it. `franktrackD`
  in this checkout is a clone, not the running daemon. The frozen `tstate/` I saw was
  simply the last publish before our reboot, not a stopped watcher.
  It has since published through 06:23 and the full tier proves the point: the same
  `seqCur >= 0` gap is **much wider than the native tier showed**. `test_set_runtime.pas`
  is now RED on **aarch64, arm32, i386 and riscv32** as well as native, plus
  `test-pascal-conformance` shards 4/6 and 5/6 — eleven open regressions where the
  native tier saw three. All target-independent, as an IR-lowering bug should be, so
  frank2-f1's one-line fix is expected to clear the whole set at once.
  **The generalisable error: "is a process running" was the wrong question** — the right
  one is "what has that host published lately", which `git fetch` answers for a watcher
  that reports over git and is deliberately on another box. A local `pgrep` cannot see
  a remote daemon and will always return the answer I wanted least.

- 2026-08-18 ~06:45 — **the red is CLEARED, and the overnight diagnosis was WRONG in a
  way worth recording.** frank2-7e (cold — a fresh context that rebuilt everything from
  the diff) landed `5b43ad800`; master is green on the three named tests.
  **The note frank2-f1 left in the tree would not have fixed it.** The cold session
  built it, ran the three tests, and they still failed identically. There were two
  defects and the comment named only the lesser:
  1. the missing `seqCur >= 0` guard — real, kept, insufficient;
  2. `AN_SET_INCL`/`AN_SET_EXCL` call `IRLowerSetBitMutate`, a **procedure**, and never
     assigned `Result`, so `IRLowerAST` returned the result slot's leftovers.
  **(2) is LATENT and predates `ce57db4cd`** — I verified this myself rather than
  relaying it: `git show ce57db4cd^:compiler/ir.inc` shows the arm already had no
  `Result :=`. While the `AN_SEQ` arm RECURSED, the leftover was a live value from the
  frame just popped and happened to be a valid IR node index. Going iterative changed
  the leftovers to `16777218` and the fold built an `IR_BLOCK` over it.
  **So the commit routed as the regressor was the UNCOVERER, not the cause** — which is
  exactly why leaving fix-vs-revert with the owner was right. A revert would have
  re-buried a real defect and looked like a success.
  Verified here before relaying: fixedpoint build at `9a40458bb`, all three tests PASS,
  and frank2's minimal repro (`c := []; Include(c, 7);`) compiles. It swept the class —
  no `AN_` arm in any of `ir.inc`'s 50 Integer-returning functions leaves `Result`
  unassigned — and removed both `a.seq` probes.
  It also resolved `bug-n-the-module-locals-cap-hides-a-compiler-stack-overflow`
  (`6d0efee09`); the two html5lib files now give ordinary diagnostics instead of a
  silent segfault. `working/` is empty. Both workers idle, trees clean.
  **Method note, from the worker itself:** it had two plausible theories before probing
  (stale spine entry; `IRDropManagedStrResult` shrinking `IRCount`) and both were wrong.
  The probe printed the raw return value. Measure, don't reason, paid again — and the
  shape-varying is what found it, since an `Include` that is the SOLE statement never
  reaches the `AN_SEQ` arm and stayed green throughout.

- 2026-08-18 ~09:00 — **pin v348, and a gap in how the pin lock is announced.** Ran
  `make stabilize-fast && make pin` (converged byte-identical, `6214284a91ca`, pushed
  `f5d85953a`) in the window where BOTH workers were idle — the cheapest possible time
  to hold a repo-wide lock. Trigger was frank3's closing note that the corpus ladder
  measures against `PXX_STABLE`, so v347 still counted `digits` and `CodecInfo` as walls
  though both are fixed post-pin; several corpus files were expected to move on the pin
  alone.
  **frank2-7e flagged what my announcement missed: I told both workers not to commit,
  rebase or push, and said nothing about BUILDING.** `make compiler/pascal26` rewrites
  the same compiler binary `stabilize-fast` is producing, so a worker build during a pin
  collides with the lock exactly as badly as a push. It held off on its own initiative.
  **The pin announcement must name builds, not just git operations** — the lock is over
  the compiler binary and `stable_linux_amd64/**`, and "do not push" is the wrong mental
  model for it.
  Also worth keeping: frank3, told to hold, **proposed a narrower permission than the
  one it was waiting on** — "clear to read, not to write" for a read-only ladder run.
  That let the post-pin measurement start immediately instead of after a round trip. Good
  shape for any worker parked behind a lock whose reason does not cover what they want to
  do.

- 2026-08-18 ~18:00 — **human left for the day; autonomy re-armed after the reboot had
  silently disarmed it.** `CronList` was EMPTY: the overnight hourly checks were
  session-only, so they died with the session the ~06:09 reboot killed, and nothing would
  have run today. Re-created as hourly at :23 (job `c4b22827`, session-only again,
  auto-expires in 7 days). **Check this at the start of any coordinator session — a
  reboot disarms autonomy without any error, and the roster's check log going quiet is
  the only symptom.**
  Live state at handoff: frank2-7e = **Track A+N** (combined, human-confirmed sole-A) on
  `bug-n-an-import-alias-binds-to-a-same-named-member-of-the-source-module` (p85,
  urgent). frank3-fc = Track B, idle by design (its queue is float work; the corpus is
  what feeds it). Track T UP on plexus, one long-standing open regression
  (`crtl_exp2.c`).
  **Blocked on the human, and it is the only thing that is:**
  `decide-how-a-compiled-def-carries-its-signature-when-boxed` (U, p88) — an OWNERSHIP
  fork behind the crashiest open bug, where two repo doctrines point opposite ways
  (normalise-don't-special-case says delete the second mechanism; the `defs.inc` comment
  says the non-owning lifetime is load-bearing). Not the coordinator's to settle, and
  **option B must not be started speculatively** — frank2-7e offered and was told to
  wait, because if A is chosen that is wasted work in a lifetime-sensitive area.

- 2026-08-18 ~18:40 — **the U ownership fork now gates TWO tickets, not one.** frank2-7e
  re-scoped the p85 (verified here: `b = a; b(1,5)` returns the ORIGINAL b — one file, no
  import, no alias) and found its only correct destination is the dynamic call path,
  which is the very path `decide-how-a-compiled-def-carries-its-signature-when-boxed`
  is about. Routing to it today would trade wrong-values for wrong-values-or-crashes.
  So `bug-n-an-import-alias-...` moved to `blocked/` behind that decision, alongside the
  p88. **Both wait on one human ruling**, and the p85 fix is straightforward once it
  lands (plan is in the ticket).
  Not waking the human: they are at work, offered to rule from their phone, and the
  worker has off-chain work — dispatched to
  `bug-n-the-last-class-in-a-module-reads-every-attribute-as-zero` (p60). Nothing is
  stalled; the decision is not urgent, only gating.
  **Pattern worth keeping, raised by frank2-7e:** three tickets today whose TITLE named
  one shape while the rule was broader (yield, procedural-value, def-rebind). The
  reporter files the shape they hit and the shape is almost never the boundary — so a
  title is evidence about the encounter, not the defect, and nothing should be SIZED from
  one. Convention in use: re-scope in the body, leave the retitle to whoever takes it.

- 2026-08-18 ~19:15 — **pin v349, forced by a coordinator error worth recording.** I
  verified frank2-7e's last-class fix with the **HEAD** compiler, saw the right values,
  and told frank3-fc the `xml_dom` ticket was unblocked. **Track B ships on
  `$(PXX_STABLE)`, and I never checked whether the fix was in it.** It was not — and
  neither were the other two:

  ```
  12275b26f  last-class hoist drain      not in v348
  3d66bdff7  cross-module defaults       not in v348
  b67db02bb  shim-class visibility       not in v348
  ```

  frank3 measured on its own toolchain instead of trusting my ordering, found the bug
  fully live there, and **refused to land a shim that would have read every nodeType as
  0** — the exact failure its two earlier refusals were right about, arriving through the
  PIN rather than through the code. Third correct refusal on one ticket, and this one
  caught the coordinator rather than the compiler.
  Pinned v349 (`596799fd9c6e`, `a6e8e763e`) and verified the repro **on the pinned
  binary** before releasing it: `1 3 9` / `1 3`, where v348 gave `0 0 0` / `0 0`.
  **The generalisable rule, which is a sharpening of one I have been repeating all day:**
  "verify against a known sha" is not enough — verify against **the binary the CONSUMER
  will use**. HEAD and `PXX_STABLE` are different grounds and a fix can be green on one
  and absent from the other for hours. A/N/P verify at HEAD; B and E ship on the pin. So
  **when a compiler fix is what unblocks a library ticket, the pin is part of the fix**,
  not a later convenience — announce it and run it before declaring anything unblocked.
  Also worth keeping: told it was blocked, frank3 did everything that did NOT need the
  pin (the ticket's own design question, the shim, the CPython half of the differential)
  and drew the line exactly at landing. That is how to spend a block.

- 2026-08-18 end of day — **the pin boundary does real work, and here is the evidence.**
  Recorded because it will next be encountered as friction. Track B refused to land a
  shim FIVE times today, and every refusal was correct. Three were the substrate being
  wrong in a new way each time (a trailing class reading its attributes as zero; a
  from-import through a shim mapping losing class attributes; an `as` rename losing what
  it renames). **Two were PROCESS, and both were mine:**
  - I verified a fix at HEAD and declared a Track B ticket unblocked without checking
    whether the fix was in the pin. All three of that afternoon's compiler fixes were
    newer than v348, so on B's real ground the bug was fully live.
  - I dispatched B at the `urllib_parse` half of a shim *because* it had identified that
    as unblocking `sanitizer.py`; it then measured that the blocker is an `as`-rename
    bug, so the shim's contents are irrelevant. The dispatch premise did not survive its
    own measurement.
  **Neither was visible from Track A/N/P, because they verify at HEAD and B ships on
  `$(PXX_STABLE)`.** The lane split is what surfaced both. So the pin boundary is not
  coordination overhead with a safety story attached — it is a second, independent
  measurement of the same tree, and today it caught the coordinator twice.
  Practical form of that, already in this file above: verify against **the binary the
  consumer will use**, and when a compiler fix is what unblocks a library ticket, the pin
  is part of the fix.
  Observation is frank3-fc's; recorded here because it belongs to whoever reads this next,
  not to the session that noticed it.

- 2026-08-18 late — **a THIRD instance of one shape: a lookup done on the SPELLING where
  declarations live under the RESOLVED unit.** Worth a deliberate grep pass by whoever
  holds A next, rather than a fourth discovery.
  - `b67db02bb` (morning): `ParseUsesUnit`'s already-compiled early exit recorded the uses
    edge against the spelling (`codecs`), not `mimic_codecs`.
  - `6cd63b836` (tonight): `ConsumeUnitQualifier`'s guard asked
    `UnitDeclaresClassExactly(alias, FindCompiledUnit(impName))` — `impName` is what the
    SOURCE wrote, so for a shim it searched the bare module name, found nothing, and the
    guard stood down for EVERY shim. Fix was one identifier: `FindUnitOrAlias` instead of
    `FindCompiledUnit`.
  - The shim-mapping family generally.
  frank2-7e, who fixed both, bets there is a fourth. **The grep is `FindCompiledUnit` and
  friends against any name that came from source text.**
  Pinned **v350** (`66f59112e1a9`, `46a6189a9`) immediately, because the worker NAMED THE
  CONSUMER unprompted — "this needs a pin before frank3 can use it" — which is the habit
  that came out of my v349 mistake. Verified the repro on the PINNED binary before
  releasing anyone this time.
  **`xml_dom` is finally unblocked after FIVE correct refusals.**
  Also worth keeping: frank2-7e caught that its OWN evidence was contaminated — the alias
  it chose to prove "no shim involved" was spelled `probe`, which is exactly the shim name
  for `mimic_probe`, so the `as` line did nothing and its own isolation table had already
  shown the no-`as` row failing identically. It then checked for a second producer, found
  none, and corrected the ticket in full. Fourth confound of the day and the first caught
  by its own author.

- 2026-08-18 hourly check (cron) — **quiet; nobody blocked, no dispatch made.** Both
  workers BUSY mid-task: frank2-7e on the rename cluster (A+N, sole-A), frank3-fc landing
  `xml_dom` now that v350 carries `6cd63b836`. Neither was messaged — they are working,
  and an idle-check ping costs them a turn for nothing.
  `working/` and `urgent/` are both EMPTY while two workers are mid-ticket. Noted, not
  acted on: both were dispatched by SendMessage and are presumably pre-claim. If it is
  still empty next check with the same two busy, ask — a lock nobody holds is how two
  agents end up in one file.
  **Track T UP**, native GREEN through `b45594911`. The `pin v349 ... RED (full)` commit
  in the log looked alarming and is NOT new breakage — checked the run record:
  `new_red: []`, and `--status` lists exactly one open regression,
  `lib-test#src:test/crtl_exp2.c` (bad=`eda43dea7629`, 16 in range), which predates today.
  The full tier reports RED because that one is still open, not because anything landed
  broken.
  Still with the human and still not urgent:
  `decide-how-a-compiled-def-carries-its-signature-when-boxed` (U, p88). It may drop from
  gating three items to two — if the rename cluster's fault turns out to be the rename
  binding rather than the callable representation, the p85 comes back to ready.

- 2026-08-18 evening — **human left for the day; yield re-estimated and settled.** Two
  challenges from Rene dismantled an estimate that had been steering dispatch all evening,
  and both were settled by ten minutes of measurement rather than argument:
  1. "I thought we already implemented yield for Pascal — minor mechanical work?" **Yes.**
     The engine is built and proven: the `yield` keyword, `AN_YIELD`/`IR_YIELD`,
     `coroutine.pas` (stackful) AND `slgen.pas` (stackless). Verified end to end —
     `; generator; stackless;` prints `0 1 2 3` today.
  2. "Isn't this the stackless optimization we deferred?" **No** — that "(later)" note is
     on **`AN_AWAIT`** (async), not `AN_YIELD`. Generator stackless is done.
  And I had to correct MYSELF on the remaining caveat: I called the `for t in obj` bridge
  the genuinely non-mechanical part without checking whether Pascal has the object form.
  It does — the FPC `GetEnumerator`/`MoveNext`/`Current` protocol at `parser.inc:19428`,
  verified (`10 20 30`). So `__iter__`/`__next__` maps onto it nearly one-to-one.
  **Net: yield is FRONTEND WIRING against three finished subsystems, not a dedicated
  pass.** The old framing is on the ticket as superseded; do not inherit it. Next for
  frank2 after the rename cluster.
  **How the mis-estimate happened, because it is the day's own lesson turned on me:**
  frank2-7e measured the STRATEGY question rigorously (19 generator functions, 76 yield
  sites, zero inside try/with) and then estimated SCOPE from the ticket's framing rather
  than from the code — and I relayed that estimate three times without reading
  `defs.inc`. That is exactly "never size a ticket from its title", committed by the
  coordinator, on a ticket whose title has already been wrong twice.
  Autonomy re-armed with fresh standing state (job `90d95108`, hourly at :23) — the
  previous prompt still described the morning's situation, which would have had the next
  check dispatching against a board that no longer exists.

- 2026-08-18 evening — **rename cluster landed as a set; pin v351; the wrong-name sweep is
  now dispatched.** Working the three tickets together was the right call — they shared a
  guard, and separating them would have produced partial fixes.
  **The length rule is DEAD, and not by the correction frank3 and I converged on either.**
  Verified on pinned v350: `name` (4 chars) returns 7 while `abc` and `run` (3 chars)
  core-dump. The real axis is the callee's RETURN TYPE crossed with a wrapper whose arity
  was hardcoded to 1; length correlated only because the working names happened to infer a
  Variant return. **Three confounds in one ticket, and the axis nobody varied this time was
  the one OUR correction introduced.** The test now sweeps lengths AND arities so no
  reading can come back.
  **A FOURTH instance of the wrong-name shape**, and this one answered a SILENT WRONG
  VALUE: a renamed class became a module alias, so `N2.somefunc()` called the module's
  function and returned 7 where CPython raises AttributeError. Verified — pinned v350
  prints 7, HEAD refuses. Same guard as the morning's shim-class fix, the OTHER argument:
  it asked whether the unit declares a class named the ALIAS while the class carries the
  SOURCE name.
  So the sweep is dispatched (Track A ticket, self-resolved under the combined-track rule).
  Four instances is a CLASS, not a run, and it is cheaper than the fifth discovery.
  Also: the boxed-def decision gates **three** items on independent evidence, not on my
  bookkeeping — frank2-7e hit the same wall from the other side (a boxed def demonstrably
  carries a code address and no signature) and confirmed p85's block rather than inheriting
  it. The defaults symptom was SPLIT OUT rather than folded, with a warning that a
  wrapper hardcoding defaults would answer for one call shape while the rest keep failing —
  which is exactly the re-measure frank3 demanded when it flagged that a crash fix must not
  close the dangerous symptom silently. **That hand-off worked across two sessions that
  never spoke to each other.**

- 2026-08-18 hourly check (cron) — **quiet; nobody blocked, no dispatch.** frank2-7e BUSY
  on yield (not pinged — it is working). frank3-fc idle by design; B's remaining corpus
  work sits behind N in every direction and inventing work for it would cost tokens for
  nothing. Nothing unpushed, `urgent/` empty, no CRITICAL.
  **Track T UP**, native GREEN through `f0d24d39e`. One open regression, the long-standing
  `lib-test#src:test/crtl_exp2.c` (16 in range).
  `working/` empty again for the second check running while a worker is mid-ticket —
  dispatches go by SendMessage and claims are being skipped. No collision risk while only
  one worker is in N's files, so raising it at frank2's next natural report rather than
  interrupting a busy session over a file move.
  **Refreshed the cron prompt (job `11f6c03d`, was `90d95108`).** The old one still
  described the rename cluster as in flight and yield as 14 files — both stale by hours,
  and the next check would have dispatched against a board that no longer exists.
  **A cron prompt is a snapshot that goes stale silently while the work moves; re-issue it
  whenever the standing state changes materially, not just when the schedule does.**

- 2026-08-18 late — **the subscript ticket's BOUNDARY was right and its AXIS was wrong**,
  which is a distinction worth keeping. Two rows nobody had crossed settled it (verified
  here, HEAD vs pinned v351):

  ```
  def f(): print((1, 2)[0])          no return  ->  WORKS even on v351
  def f(): return [1,2,1].count(1)   a METHOD   ->  SEGFAULT on v351
  ```

  So the subscript is innocent: it is **RETURNING anything derived from a container
  literal**. `PyInferDefRetType` typed the return from a token scan whose literal arms
  Exited on the OPENING bracket, so the def registered a `tyClass` result and the
  container came back through a class slot.
  **Why a clean four-axis crossing still named a correlate:** the "a subscript yields a
  VARIANT" rule already existed, but it lives in the arm keyed to an IDENT receiver, so a
  literal receiver never reached it. The reporter's scan was sound and the axis it named
  was a true correlate — **crossing beats walking and still does not guarantee the
  mechanism.** Both workers were told this explicitly so it does not read as a miss.
  Fix written as "a literal is not always the whole expression" rather than as a subscript
  case, which is why it also fixes a `.count(1)` row that was never in the ticket.
  Pinned **v352** (`0d2087d629bf`, `b14da0847`) because the fix unblocks a REGISTERED
  Track B workaround — the platonic ParseResult `__getitem__` core-dumps on v351 and
  returns `x` on v352. The worker flagged the consumer itself; that rule is now being
  applied by the workers rather than by me.
  **Self-inflicted, recorded so the next coordinator does not repeat it:** I put backticks
  inside a bash-quoted `git commit -m`, and command substitution silently ate the span —
  `b14da0847`'s message has a hole where the repro should be. I did NOT force-push over a
  pushed pin commit to fix prose while two sessions pull from master; a gappy message is a
  far better outcome than rewritten history under a worker's feet. **Never put backticks
  in a bash-quoted commit message.**

- 2026-08-18 hourly check (cron) — **quiet; nobody blocked, no dispatch.** frank2-7e BUSY
  on `bug-n-a-from-import-of-a-compiler-provided-module-binds-no-names` (p55) — not pinged.
  frank3-fc idle by design. `working/`+`urgent/` empty, nothing unpushed, no CRITICAL.
  **Track T UP**, native GREEN through `2f4119b1f`; one open regression, the long-standing
  `crtl_exp2.c`.
  **Fixed the cron design rather than re-issuing it a third time.** The prompt had gone
  stale within an hour on each of three versions — it still named yield as in-flight after
  it was parked, and listed super and the subscript bug as unclaimed after both landed.
  A stale snapshot is WORSE than none: it invites dispatching against a board that no
  longer exists. The prompt now carries only DURABLE facts (lane rules, the pin/ground
  distinction, the theme, the yield-is-scheduled-not-queued call, claims discipline) and
  tells the check to read standing state from disk — `tail -120` this file, plus
  `progress.sh ready` and `ls working/`. Job `9108876a`, was `11f6c03d`.
  **Generalisable: a recurring prompt is CODE, and embedding mutable state in it is the
  same mistake as a dated scan in a long-lived ticket.** Put the state where it is
  maintained and have the prompt fetch it.

### 2026-08-18 evening — banking the day

Verified `feature-nilpy-subclass-a-builtin-type` (`1cbe666b5`) myself on a fresh
fixedpoint at HEAD, A/B against the v352 pin:

```
class X(list): len() on a subclass       HEAD=2       PINNED=error: unknown base class list
class D(dict): in / iteration            HEAD=True 1  PINNED=error: unknown base class dict
str stays refused, better message        HEAD=error: str cannot be subclassed — value type
non-container class still raises on len  raises on both
```

**Two corrections from frank2 worth keeping, both of them about MY reasoning.**

1. *The identity-vs-kind shape.* `rec <> REC_UCLASS_BASE + FindUClass('TPyList')` was an
   IDENTITY test doing duty for a KIND question — exact until something could descend from
   a container, silently wrong the moment `class X(list)` could. The tell: **the runtime
   was right all along and only the compiler disagreed** (`pylen_v` tests `o is TPyDict`,
   which Pascal answers through the inheritance chain). Sibling of today's
   `ProcUnitIdx >= 0` standing in for "is a Pascal facade". Same family, one memory.
   Corollary that saved the session: `class X(TPyList)` — pylib's own spelling — **already
   compiled**, which turned a presumed object-model pass into a predicate fix. *Before
   sizing a feature as missing, try it in the implementation's own vocabulary.*

2. *My p55 rerank was sequencing-blind.* I ranked `_utils.py` up as a chokepoint;
   frank2 measured that it does not move at all, because it stops on
   `no unit named xml_etree_elementtree` long before reaching `MethodDispatcher(dict)`.
   The chokepoint argument is real but only pays out **after** Track B's shims land. Same
   trap as the yield reach count: a first-wall table cannot see what is behind the wall.

**Banked here deliberately.** Queue state clean — nothing claimed, `working/` empty,
everything pushed. The remaining unclaimed N items are p50/p45; the highest-value item
(`feature-nilpy-yield-outside-a-for-loop`) is **scheduled work, not queue work** and is
reserved for a fresh session with room, per the user's call. Compile count sat at **6/48**
all day while a great deal moved — that is the past-a-wall / onto-the-next-wall split
doing its job, not a stalled campaign.

**Both workers confirmed clean before close.** `working/` empty, nothing claimed, nothing
unpushed on either side. One file in `unfinished/` carries frank3's name only as "Found
by" — `bug-n-calling-through-a-function-alias-with-a-default-omitted-segfaults`, track N,
p88, owner unassigned, parked behind the boxed-def decision. Not a lock and not an orphan.

**frank3's sharpening of my pin rule is the version to keep**, because it is better than
mine. I wrote it as a procedure (verify against the binary the consumer will use); frank3
wrote it as two claims: *"fixed at HEAD" and "unblocked for B" are different claims, and
the second needs its own measurement.* That is what actually stops the error — the failure
was me asserting claim two having measured only claim one. Of the five refusals frank3 hit
that day, three were the compiler and two were this gap. Now a memory.

**Open lib-test red is a false positive, for the second time under that key.**
`lib-test#src:test/crtl_exp2.c bad=eda43dea7629`. Re-proven innocent tonight rather than
dismissed from memory, **because the pin moved twice today** (v351 `a6d6dfb84`, v352
`b14da0847`) and that is precisely the confound that would make "just the timeout again" a
wrong dismissal. The commit touches `Makefile`, `parser.inc`, a ticket and a test; nothing
under `stable_linux_amd64/**` or `lib/**`; its Makefile hunk is a **test-core** step; and
lib-test runs the PINNED compiler, which at that sha was still pre-v351. Reranked
`chore-t-split-lib-test-into-jobs-that-name-what-failed` 35 → 55 and told plexus-T, with
the reasoning open to its pushback since the tooling is T's: the hazard is no longer the
false red but the *next* one, because a genuine C-math regression under that key now
arrives pre-discredited.

**Open with the user tomorrow:** the boxed-def decision (`decide-how-a-compiled-def-carries
-its-signature-when-boxed`, p88) is still with them and gates two items; and Track B's
opening question is whether a real XML library is in scope, which frank3 correctly refused
to settle by itself — if the answer is anything other than a thin shim, that is a `decide-*`,
not an absorbed assumption.

**Correction to the entry above, from plexus-T (`78c9859c7`) — my citation was stale.**
I justified the crtl_exp2 dismissal with "a timeout is a duration signal, so bisecting it
is arbitrary", citing T's closed ticket. **T narrowed that rule hours earlier and the
closed ticket still states the old, too-broad form.** The live rule: refusing a
timeout-bisect is right only when the expensive step existed across the WHOLE range; if
the range SPANS the commit that first made the step execute, the landing is EXACT (found
via `callbacks.npy`, where a timeout bisect converged correctly).

It mattered here rather than being pedantry: this job's sources include
`examples/tk/hello.npy`, and `5215148bb` is what first made the tk tests execute under
`timeout 120 xvfb-run`. Had it fallen inside the 16-commit range, this was the exact shape
and my false-red conclusion would have been **wrong**. T checked — `5215148bb in range:
False` — so the tk step ran throughout, the landing is arbitrary, and the conclusion holds
under the narrowed rule as well as the old one. Right answer, insufficient reasoning.

**Also worth keeping: T's `pin_immune()` correctly REFUSED to exonerate `eda43dea7629`**,
because it touches `Makefile` and `test/**`, which a pin-built job genuinely reads. What
carried the proof was per-target hunk analysis (the Makefile hunk invokes `./$(COMPILER)`,
so it lands in `test-core`). T deliberately leaves that un-automated — Make targets share
variables and dependency edges, so textual proximity is not causal isolation, and a wrong
exoneration hides a real regression silently. **A reading agent may do what an unattended
rule should not.** Both caveats are now in the pin memory; anyone quoting the closed
ticket for "timeouts are unbisectable" is quoting something superseded.

T is not taking the split (its user wrapped the session for a clean context). Ticket is
p55, unclaimed, both halves and the baseline recorded.

**Resolved (`d483dd50e`).** T put the correction as a banner **above the body of the
closed ticket**, not only in the playbook — because that is the artifact someone finds
when they search "timeout bisect" with a converged range on screen. Nobody greps a
playbook when they already have an answer in front of them. The banner tabulates both
shapes, carries the `callbacks.npy` counter-example, and records the coupling: fixing the
inner-timeout ticket will start refusing CORRECT bisects unless the guard learns the
distinction, so those two land in one commit.

**The general rule both of us hit tonight, from opposite sides.** T narrowed a rule and
updated `track-t.md` plus its own working memory, leaving the closed ticket stating the old
form — *"I corrected the DERIVED artifact and not the SOURCE one; I checked whether the
rule was right where I wrote the correction, not whether it was right everywhere it is
stated."* I then quoted the source artifact and got a right answer by luck. **Being closed
is what makes a ticket dangerous: never revisited, still ranks in search.** After narrowing
or reversing any rule, grep every place it is stated — `done/` included — and put the
correction where a searcher lands. Now in the stale-prose memory alongside "a dated scan
reads as current forever", which is the same hazard in a third costume.

Each of us found the other's version of one error in a single exchange. That is the
arrangement working, and it is worth noting that it took **disagreement** to produce it —
T agreed with my conclusion and attacked my method anyway, which is the harder and more
valuable review.

- **check 2026-08-18 (post-bank):** quiet, nobody blocked, and that is deliberate — the day
  was banked, not stalled. `working/` and `urgent/` both empty; frank2-7e, frank3-fc and
  plexus-T all idle with clean queues confirmed by each. T UP, native GREEN through
  `118c4c42a5b3`; the single open red is the documented `crtl_exp2` false positive (now
  carrying a correction banner at `d483dd50e`), not new breakage. Commits since T's last
  tested sha are docs/roster only. **No dispatch:** the ranked N remainder is p50/p45, and
  yield is scheduled work reserved for a fresh session per the user. Nothing invented.

- **check 2026-08-18 (+1h):** still quiet, nobody blocked, no dispatch. `working/` and
  `urgent/` empty; all three workers idle. **Real state change worth recording: the FULL
  matrix caught up to today's head** — it had been trailing at `8a7418902cf4` and has now
  run at `118c4c42a5b3`, alongside `slow` GREEN, `opt` GREEN and a bench run (30 rows, 550
  conf). Verdict is RED, and I checked the run record rather than trusting the durable
  fact: `new_red: []`, `still_red: ["lib-test#src:test/crtl_exp2.c"]`. So the ONLY red
  across the whole matrix at today's head is the documented false positive — every real
  job green on every tier. That is the strongest signal of the day and it arrived after
  the bank: today's four N landings plus the P and A fixes hold up under the full
  cross-target sweep, not just under `quick`.
- **checks 2026-08-18 (+2h through +5h):** unchanged — zero commits since `fb2829cf2`, `working/`
  and `urgent/` empty, all workers idle, T UP with the same single documented
  false-positive red. Nothing to dispatch; day stays banked. *(Rolling one entry forward
  rather than appending an identical line per hour — a quiet check log should not outgrow
  the state it records.)*

- **check 2026-08-18 (+6h) — user flagged both workers idle; unbanked and dispatched.**
  Banking was my call and it was wrong to hold once the user was paying for idle capacity.
  Reading the queues rather than my memory of them turned up a real defect:

  **The corpus's largest lever had no ranked ticket.** The missing-module shim job was
  measured across four ladder scans and lived only inside
  `feature-nilpy-thirdparty-libraries-as-targets` — a META ticket parked in
  `unfinished/`, which `ready`/`next` do not read. So `ready --track B` topped out at
  **p30** (a float-ULP bug at p20 was in view) while that ticket's own conclusion said
  *"Track N is no longer the bottleneck for this ladder; everything blocking is Track B
  shim work."* The queue was not empty — it could not see its own top item. Third instance
  of `feedback_measuring_a_thing_is_not_filing_it`, and the most expensive, because it
  presented as *no work available*.

  Filed `feature-b-the-module-shim-batch-blocking-the-python-corpus` (B, **p62**), now top
  of B. Three guards written into it: (1) **re-measure first** — every count is a dated
  snapshot from `c61b43390`, and four N fixes landed 2026-08-18 that can move files past
  walls it still lists; the parent records two scans disagreeing because the pin moved
  under one of them; (2) the `_utils.py` **sequencing trap** (a first-wall table cannot see
  what is behind the wall — count users, not first walls); (3) the **XML scope fork is
  fenced off** — thin shims only, and anything more is a `decide-*`, not an absorbed
  assumption.

  Dispatched frank3→shim batch (B), frank2→`bug-n-a-builtin-types-method-cannot-be-called-unbound`
  (N, p55). **Explicitly withheld yield** despite it ranking higher at p58: both sessions
  are 13h old and its failure mode is silent stack corruption, which is the worst thing to
  chase on a tail-end context. Both told to decline if thin — a half-landed Track A change
  is the one state that breaks the gate for everyone — and reminded that `working/` is the
  lock, since a SendMessage dispatch does not claim.

- **check 2026-08-18 (+7h) — the shim dispatch died at step one, and that is the guard
  working.** frank3 re-measured at pinned v352 (`0d2087d6…`) and **the batch does not
  exist any more**: 12 `mimic_*` units are on disk under `lib/rtl` and gated by
  `lib-test`. I filed p62 against a table describing a world that had already ended.
  The ticket survived its own premise dying **only because step one was a re-measure
  rather than a shim** — a guard I wrote in because the parent ticket recorded two scans
  disagreeing over a moved pin. Paid for by an earlier mistake, repaid same day.

  **Sharper than the staleness: the old counts could not be diffed against the run at
  all.** They counted `six` at 13 and `webencodings` at 6, but the ladder scans
  html5lib/tinycss2/webencodings = 48 files, and `reportlab` is present without being a
  rung. Whatever produced those numbers was not this instrument, so frank3 **replaced**
  the table instead of updating it. Reconciling two instruments yields a number
  describing neither.

  **THE CAMPAIGN'S STANDING ASSUMPTION IS INVERTED.** Remaining module-blocked files:
  **8**, four of them behind one Track U decision. Remaining LANGUAGE walls: **32**, of
  which **`yield` alone is 18 — more than every missing-module row combined.** So
  *"Track N is no longer the bottleneck for this ladder"* was true when written and is now
  **superseded**; Track B's corpus lever is one decision wide. Reranked
  `feature-nilpy-yield-outside-a-for-loop` **58 → 75** with a banner carrying both the
  measurement AND the dispatch constraint — raising the number is precisely what would
  otherwise hand a silent-stack-corruption hunt to a tail-end session.

  **frank3 caught a pin claim of mine, again.** The two-arg super fix `60d5a6c432` is NOT
  an ancestor of pin `b14da0847` — verified here, not relayed. My ladder-facing wording
  said "cleared" where it should have said "cleared **at HEAD**". Second instance today of
  the same gap; frank3's two-claims framing is the fix and is now a memory.

  frank3 filed `decide-xml-etree-thin-tree-model-or-a-real-xml-library` (U, p62) with the
  surface measured FIRST, so it is answerable in one read: html5lib uses ElementTree as a
  **tree model, not an XML library** (3 factories, 10 members, no parse/fromstring/XPath/
  serialiser), plus one exact quirk — `Comment("x").tag` **is** the `Comment` function.
  Told frank3 to stop: B's queue genuinely tops out at a p30 float-ULP bug, and confirming
  that beats filling its capacity. **Loose end flagged, not resolved:**
  `feature-b-mimic-urllib-request-over-the-rtl-http-stack` sits at p30 while
  `lib/rtl/mimic_urllib_request.py` exists — stale ticket or means more than the file;
  checked, not assumed.

  **Loose end closed (verified, one read):** `feature-b-mimic-urllib-request-over-the-rtl-http-stack`
  is NOT stale. `lib/rtl/mimic_urllib_request.py` is a **present-and-refusing stub** —
  it exists so importing code compiles; `urlopen`/`urlretrieve` raise `NotImplementedError`
  (confirmed at lines 44-51); `Request` is real only because holding what it was handed is
  side-effect free. The ticket is for the real `urlopen` over `lib/rtl/http.pas`. **The
  file existing is the ticket's premise, not evidence against it**, and its summary line
  already opens with "REFUSES". General shape recorded as a memory, because it will recur
  as the shim set grows: **a board reader cannot distinguish a refusing stub from a working
  module by looking at the tree** — never de-rank on "but the file is there". Convention
  deliberately NOT adopted off one instance (frank3's call, and the right one): if a second
  refusing shim appears, put REFUSING in the summary's first clause rather than inventing a
  status field.

  **frank3 stopped as agreed** — tree clean, nothing held, `working/` empty, last commit
  `5d7894926`. frank2 still working Track N.

- **check 2026-08-18 (+8h):** healthy, nobody blocked. frank2's dispatch **landed**
  (`7da43daa9` fix(N/A): a builtin type's method, called unbound; ticket in `done/`), and
  it filed the sibling `bug-n-a-builtin-subclass-subscript-operator-skips-the-override`
  (p55) rather than folding it in — right call, and the expected "one concept, N sites"
  shape falling out of today's subclass work. No report came to me; git carried it, which
  is fine. `working/` and `urgent/` empty, T UP and native GREEN through `9cd170aec1c3`.

  **Holding the yield line.** It now tops Track N at p75 and both local sessions are 14h
  old. That combination is exactly what the banner exists to prevent — a
  silent-stack-corruption hunt handed to a thin context because `next` ranked it first.
  Not dispatching it; it waits for a fresh session.

- **COORDINATION GAP, mine, found 2026-08-18 evening: I never read Track A's queue.**
  The cron check prompt names `ready --track N` and `--track B`, and I followed it
  literally all day. Track A's queue was never opened. Sitting in it, second from the top:
  **`feature-port-freebsd-native` — p55, unblocked, ready, "unblocks 1"** (FreeBSD/amd64
  native target: raw-syscall ELF, own syscall table, carry-flag error convention, ELF
  brand), plus `feature-port-openbsd-libc` (p50) and `feature-port-multi-os-abstraction`
  (p55, umbrella). The platform machinery already exists — `--platform=posix|esp`,
  `lib/rtl/platform/{posix,esp}`.

  **Worse than tonight's shim miss, not better.** That ticket was genuinely unfiled; this
  one was filed AND ranked correctly and I simply never looked. A prompt that enumerates
  *some* queues reads as enumerating *the* queues — the omission is invisible from inside
  the loop, exactly like a first-wall table cannot see what is behind the wall.
  **Fix: read `ready` for EVERY staffed lane, not the ones a prompt happens to name.**

  Surfaced to the user because it directly answers what they were weighing — MINIX
  (academic) versus BSD (real). The honest answer is that they are different axes:
  FreeBSD is the **platform** axis (cheap, useful, ranked, and the thing that forces the
  OS abstraction into existence), MINIX is the **freestanding** axis (kernel, no libc
  beneath, boot) which no application corpus or BSD port can teach. Sequencing note added
  to `decide-which-minix-is-the-target`.

---

## STANDING MANDATE — coordinate for one week (user, 2026-08-18)

> "You coordinate. We will evaluate results after a week. And I hope NilPy gets over the
> bump."

**Evaluate: 2026-08-25.** This section is the charter for every coordinator session in
between — it outlives any one context, so read it before the check log.

### What "NilPy over the bump" means concretely

**THE ORIGINAL BUMP IS CLEARED (2026-08-19).** This section is rewritten rather than
appended to, because its old text — *"`yield` IS the bump"* — was a durable fact with a
finishable subject, and it finished.

`feature-nilpy-yield-outside-a-for-loop` is in `done/`. The generator series landed and
**removed the 18-file `yield` wall outright**, the largest single lever the ladder has ever
recorded. Measured by frank3 at pin **v353** (`256183a5f52c`):

| | compiled |
| --- | --- |
| at v352 | 6/48 |
| at v353 | **10/48** |

**All four of that gain belong to the generator series, not to the ElementTree shim that
landed beside it** — frank3 proved the attribution by running a same-pin A/B first (6/48
with the shim moved aside AND back) before re-running on v353. Had it only measured after
the pin, the shim would have been credited with the generators' work. That is the
past-a-wall discipline working, and it is worth imitating exactly.

### CORRECTED 2026-08-19 (later): the bump is `decode(..., final=)` — 12 files

**The section below named `Mapping` (7 files) as the new bump. It is second.** A clean
ladder re-run on pin v357 (`ebcf15ccb1046b29353b3b85091a8cdc`, captured before and unchanged
after) reads **10/48 — byte-identical to v353 across all 15 wall categories.** Nothing moved
in that whole span, which covers the Mapping shim, the def-signature work and three pins.
**Past a wall: zero. Onto the next wall: zero.**

The ranked table names the real top lever:

| files | wall |
| --- | --- |
| **12** | **`decode has no parameter named 'final'`** |
| 7 | `unknown base class Mapping` |
| 3 | `undefined variable (property)` |

**Top two rows = 19 of the 38 non-compiling files**; the rest is a long tail of ones and
twos. It **had no ticket** — the second time on this campaign a top lever was measured and
unfiled. Now `bug-n-a-user-classs-decode-method-is-hijacked-losing-its-own-parameters`
(N, p70), filed with the measurement that reframes it: **webencodings declares
`def decode(self, input, final=False)` on its OWN class**, and `lib/rtl` has no
`mimic_codecs.py` — so this is a call binding to the wrong `decode`, **not** a missing shim
parameter. Suspected sibling arm of the fixed keys/items/values dict-view hijack; marked
unverified in the ticket, with instructions to fix the predicate rather than the list.

**Caveat carried honestly:** that run omitted `--files`, so "the same 12 files" is not yet
established — identical histograms make a swap unlikely but cannot exclude one. Re-run in
flight.

### The previous bump (still real, now second): `unknown base class Mapping` — 7 files

With `yield` gone, the top wall in html5lib is `collections.abc`:

    unknown base class Mapping     7 files (was 3)

All four `xml.etree` files are on it, having moved past `unknown base class dict` (fixed
by `feature-nilpy-subclass-a-builtin-type`, now `done/`). Nothing else is close in size.

**It had NO TICKET** until the coordinator filed one on 2026-08-19 —
`feature-b-mimic-collections-abc-mapping-and-mutablemapping` (B, p68). Measured, not
assumed: `lib/rtl/collections.pas` exports no `Mapping`, there is no
`mimic_collections_abc.py`, and each of the four importers wraps the import in
`try/except ImportError` with the pre-3.3 `from collections import Mapping` fallback, so
**both spellings must resolve** or the fallback masks the real error.

**It is genuinely blocked, and the two blockers did not look like blockers.** A `Mapping`
ABC exists to supply mixin methods derived from `__getitem__`/`__len__`/`__iter__`, and
two bugs frank3 filed the same session hit exactly that surface:

- `bug-n-a-user-classs-keys-items-values-is-dispatched-as-a-dict-view` — three of the seven
  methods `Mapping` provides, segfaulting or answering garbage through an untyped receiver;
- `feature-nilpy-for-loop-getitem-protocol-fallback` — the iteration half; `list(obj)`
  compiles and returns `[]`, which is the worse failure.

Neither ticket's own framing showed it was load-bearing for 7 corpus files (the second was
filed at p25). **Prio propagation down the new dependency edges reranked both to p68
automatically** — no manual rerank was needed, which is the ranker working as designed.

### The dispatch rule that must not be broken

**RETIRED AS WRITTEN 2026-08-19** — it named `feature-nilpy-yield-outside-a-for-loop`
(p75, "fresh session only, its failure mode is silent stack corruption in
`PyEmitParamSpills`"). That ticket is `done/`. Same finishable-subject trap as the section
above; the rule is kept in its general form because the reasoning outlives the ticket:

**A ticket whose failure mode is SILENT CORRUPTION rather than a compile error goes to a
fresh session, regardless of what `next` ranks first.** A long-running context is exactly
where a silent wrong value gets rationalised instead of measured. When such a ticket
exists, its banner says so and the banner outranks the queue order.

### Standing coordinator rules for the week

- **Read `ready` for EVERY staffed lane** — A, N, B, C, T — not the ones a check prompt
  happens to name. Following the prompt literally hid a ready, unblocked, p55 Track A
  ticket (`feature-port-freebsd-native`) from the coordinator for an entire day. A prompt
  that enumerates *some* queues reads as enumerating *the* queues.
- **Never decide a `decide-*`.** Eight are queued for the human, four freshly framed.
  Escalate, don't guess — that is the whole of Track U.
- **Verify, then name the sha.** HEAD and `PXX_STABLE` are different grounds. "Fixed at
  HEAD" and "unblocked for B" are two claims and the second needs its own measurement.
  Both errors happened on 2026-08-18; both were caught by workers, not by me.
- **Idle is a valid state.** Target 1-2 workers plus the coordinator. Hunt for blocked;
  never dispatch to fill capacity. But **do not bank a day while the user is paying for
  idle capacity** — that call was made once and was wrong.
- **The coordinator writes no code.** Filing, ranking, routing and verifying only.
- **DISCARDING ON SUSPICION IS CORRECT; RECORDING THE SUSPICION AS A FINDING IS NOT.**
  frank3's line, 2026-08-19, and the sharpest thing to come out of the v357 incident.

  It binned a ten-minute `lib-test` believing a pin had swapped under it, wrote
  "killed & log binned", and **had the disproof in its own scrollback** — a mid-suite hash
  sample at 130 targets still reading `540956f1f071`/v356. The kill was right on the
  information it had. What was wrong was promoting the suspicion to a fact: *"a half-swapped
  suite has no interpretation at all"* was true of the hypothetical and never established of
  that run.

  **The coordinator then propagated it** — wrote the contamination into this roster as fact
  and apologised for causing something that never happened. That is the cost: ten minutes is
  cheap, a suspicion recorded as a finding travels.

  **How to apply:** discard freely, but write "discarded — could not rule out X" rather than
  "was contaminated by X", and before recording, check whether you already hold the evidence
  that settles it. A suspicion strong enough to act on is not thereby strong enough to
  publish.

- **A STALE READ IS NOT A MISSING ARTIFACT.** Same day, the coordinator reported two of
  frank3's artifacts as absent from origin and quoted a superseded line from a ticket; both
  were present, and the pull had simply landed between frank3's message and its push.
  **`git fetch` immediately before asserting anything about origin's state** — and prefer
  `git cat-file -t origin/master:<path>` over reading the working tree, which answers a
  different question. Third instance today of a true statement about the wrong subject, and
  this one was made while correcting someone else for that exact class.
- **THE WORKERS ARE IN SEPARATE CLONES — the pin lock is NOT what it was assumed to be.**
  Verified 2026-08-19: `/home/rene/frank2`, `/home/rene/frank3` and the coordinator's
  `/home/rene/frankonpiler` each have their own `.git`. (Note this differs from CLAUDE.md's
  "no worktrees/clones" line; reality, not the doc, is what the lock has to model.)

  **So `make pin` in the coordinator's clone CANNOT swap `$(PXX_STABLE)` underneath a suite
  or benchmark running in a worker's clone.** A worker's tree changes only when **it**
  pulls. The mixed-compiler hazard is real but its trigger is *the worker pulling
  mid-measurement*, not the coordinator pinning.

  **What actually crosses clone boundaries: the CPU, and nothing else.** One box, so a
  `stabilize-fast` is heavy load on a neighbour's benchmark — the interleave-and-take-min
  reasoning stands. File-level hazards do not cross.

  **Correction, and it is a sharp one: the PROCESS TABLE crosses too, and that makes
  `pkill -f` a cross-clone weapon.** Found 2026-08-19 the expensive way. frank2 was told
  its ladder run was redundant, ran `pkill -f "nilpy_ladder.py"`, and killed **frank3's**
  run in another clone — a pattern match on a command line has no idea which checkout the
  process was launched from. frank3's output file was left at **0 bytes**, and the loss was
  not noticed until the coordinator went looking for the results.

  So the clone boundary protects **files** and nothing else. Anything keyed on a
  process name, a port, a `/tmp` path, or a lockfile is shared ground for every agent on
  this box.

  **Rules, all three learned from that one incident:**

  - **Kill by PID, never by pattern.** You launched it, so you have the PID; `pkill -f` is
    only ever right when you are certain you are the sole user of the box, and on this box
    you never are.
  - **`setsid` long runs** so a stray pattern kill cannot take them with a sibling's, and
    write output to a path carrying your agent name.
  - **When you tell a worker its work is redundant, say what to kill.** The coordinator's
    share here is real: "your run is redundant" without "kill only your own PID" is an
    instruction to stop, and pattern-killing is the obvious way to obey it. An instruction
    that leaves the dangerous method as the obvious one is an incomplete instruction.

  **Therefore:** still `pgrep` and hold before a lock (CPU is a real reason), but do not
  tell a worker its files are at risk from a pin — they are not. The protection a worker
  actually needs is its own: *do not `git pull` while a measurement is in flight*, plus the
  before/after toolchain-hash capture, which detects it without needing anyone to
  coordinate.

  **How this was got wrong:** the coordinator and frank3 independently reasoned about a
  shared working tree, agreed with each other, and one apologised for a contamination that
  may never have happened — a worker binned a possibly-good ten-minute run on that basis.
  **Two agents agreeing is not corroboration when both inherit the same unexamined
  premise.** Same family as reading three "idle" signals that were all about the wrong
  subject.
- **ASK BEFORE TAKING THE LOCK, DO NOT ANNOUNCE AS YOU TAKE IT — and check yourself so it
  does not depend on anyone replying.** Learned the hard way 2026-08-19: the coordinator
  messaged "hold builds" and started `stabilize-fast` in the same breath. frank3's
  "hold, my `lib-test` is in flight" arrived **after** the pin had already swapped
  `stable_linux_amd64/default/pinned`. By construction the reply could not have arrived in
  time. **Announcement is not coordination.**

  **Before every lock:**

      pgrep -f 'make (lib-test|test|demos|test-nilpy)'

  One command, no round trip, and it does not require the other agent to be awake. Then ask
  and *wait* if anything is known to be running.

  **RUN IT AS ITS OWN COMMAND. Do not chain it to the build.** Second failure of the same
  lock, 2026-08-19, and the rule above did not prevent it because it says *what* to run and
  not *how*. The coordinator ran

      pgrep -f 'make (lib-test|...)'; set -o pipefail; make stabilize-fast ... && make pin

  in **one shell invocation**. The pgrep did its job — it printed frank3's two live ladder
  PIDs — but its output and the pin's output arrived together, after the pin was done. So
  the check ran, produced the right answer, and had **no effect whatsoever** on the
  decision it existed to inform.

  **A check whose output you do not read before acting is not a check.** It is a record,
  written after the fact, that you had the information and did not use it — which is worse
  than not checking, because the transcript now shows diligence that never occurred. The
  same shape as `pgrep`-matching-its-own-waiter elsewhere in this file: the command was
  correct and the *wiring around it* was what lied.

  **Therefore: separate tool call, read the result, then decide.** No `;`, no `&&`, no
  chaining a check to the thing it gates — anywhere, not just here. If a check is worth
  running it is worth a round trip, and if it is not worth a round trip, delete it rather
  than keeping it as decoration.

  **frank3's sharpening, which is the better statement of the rule and is kept in its
  words:** *"the fix is structural rather than attentional: the check has to be able to
  **stop** the thing it is checking, or it is a log line."* The version above still describes
  an act of care. This one names the property, and it is testable — point at the check and
  ask what it can halt. If the answer is nothing, it is telemetry, however conscientious it
  looks in the transcript.

  *(Harm that time was bounded, and bounded for a reason worth remembering rather than a
  lucky one: workers run in SEPARATE CLONES, so a pin cannot swap `pinned` under a peer's
  run — only CPU crosses. The cost was that frank3's ladder measured v357 while wanting to
  measure v358, i.e. a wasted run, not a corrupt one. Do not generalise the safety: it
  holds because of the clone boundary, and would not hold for two agents in one checkout.)*

  **Why a half-swapped suite is worse than a half-swapped A/B:** an A/B at least compares
  two things you chose; a suite built half on one compiler and half on another **has no
  interpretation at all**, and it will very likely still print green. A worker's
  before/after hash check cannot save it either — a suite is not a comparison, so the hash
  only says "discard", ten minutes late.

- **A PIN THAT FIXES A KNOWN RED MUST BE CHECKED AGAINST THAT RED BEFORE THE PIN COMMIT
  LANDS.** `stabilize-fast` proves the fixedpoint; it says nothing about the defect you are
  pinning to fix. Run the failing repro against the new `pinned` binary first, and commit
  only on that. Earned by the first v357; applied on the second (callbacks/htmlview/hello
  all `ok` before the commit).
- **GATE AGAINST THE NEW PIN, NOT BEFORE IT — demonstrated 2026-08-19, not argued.**
  Track B ships on the pin, so the meaningful green is the one taken against the pin the
  compiler commits produce. frank3 proposed this an hour before it mattered; it then caught
  v357, which would otherwise have sat **blessed and red** while frank3 reported its ticket
  green against v356. **Both reports would have been true and the ground broken.** Do not
  accept pre-pin gating again without a specific reason.

- **REVERTING A BAD PIN: `make revert`** — fixed 2026-08-19
  (`bug-a-make-revert-the-documented-pin-brake-does-not-fire`). It used to copy a
  per-version `vN` binary this tree stopped keeping and died with "Binary … missing";
  it now restores every tracked file under the stable dir from the commit that pinned
  the previous version, so `pinned`, `VERSION`, `pin.log` and the frozen `builtin/`
  come back byte-for-byte. Bare `make revert` steps back one pin, repeatably;
  `make revert VERSION=N` goes straight to a named one. It leaves the result **staged,
  not committed** — same contract as `pin` — and `git checkout HEAD -- <the dir>` undoes
  the undo. Exercised against real v365→v364→v363→v362 pins in a scratch clone.
  Hand-reverting the pin commit still works and is what recovered v357 → v356
  (`5a0e894b3`). **The commits stay on master; only the blessing is undone**, which is
  what the brake is for.

- **A WRAPPER THAT APPENDS ANYTHING AFTER THE COMMAND UNDER TEST REPORTS THE WRAPPER'S
  HEALTH, NOT THE TEST'S.** `; echo exit=$?`, `| tail`, `&& next` — all three, and all
  three look like diligence. frank3 hit `make lib-test > log 2>&1; echo exit=$?` reporting
  success while the suite was `Error 1`, **immediately after finding the same shape in the
  coordinator's pin pipeline**, which says how well it hides. Read the log, or use
  `set -o pipefail` and check the real status.
- **SEVERAL IMPROVEMENTS THAT REDUCE THE SAME QUANTITY DO NOT MULTIPLY.** frank3's rule,
  from a prediction of ~4x that delivered 1.6-1.8x:

  > When several improvements all reduce the same underlying quantity, they do not multiply
  > — and a list of independent-sounding mechanisms is exactly what makes them look like
  > they do.

  The ticket listed three effects (half the limbs; a five-pass multiply collapsing to one;
  a bigger chunk halving the setup rounds) and compounded them. They were not three
  effects — they were three **descriptions of one quantity**, limb operations, which an
  instrumented counter says fell 2.2x. **Every individual claim was true, which is what
  made the double-counting persuasive.**

  **The remedy, and it belongs BEFORE the prediction rather than after the shortfall:
  count the quantity, do not enumerate the reasons it should drop.** Applies directly to
  ranking and sizing — a coordinator reading "three independent wins" in a ticket should
  ask whether they are three levers or three views of one.

  Companion discipline from the same report: **record a gate as UNMET rather than reframing
  the target.** Predicted ~4x / 2-3 µs, delivered 1.6-1.8x / 6.6-7.0 µs, recorded as
  not met — while separately arguing the change earns its place on other grounds (2.2x less
  work, a dead routine deleted, a simplification not a speed hack). Two different claims,
  kept apart.
- **"A PIN IS DUE" AND "SOMEONE IS BLOCKED ON A PIN" ARE TWO DIFFERENT CLAIMS.** The
  standing rule to pin whenever `compiler/**` moves makes it easy to read the first as the
  second, and then to override a worker's measurement for a hygiene condition. Check who
  actually asked — `working/`, and the messages — before treating a due pin as urgent.
  2026-08-19: a worker offered to sacrifice a 10-minute benchmark because it believed
  "other lanes are waiting on those compiler fixes"; nobody was, and the honest answer was
  to decline the courtesy and correct the premise.

- **CAPTURE THE IDENTITY OF WHAT YOU MEASURED, DO NOT RELY ON A PROMISE THAT IT DID NOT
  CHANGE.** frank3's rule, adopted here and better than the coordination it replaced:

  > A benchmark should record the identity of its toolchain rather than depend on a promise
  > that nobody changed it.

  It recorded `md5sum stable_linux_amd64/default/pinned` and VERSION **before** an A/B run
  and re-checks them after — mismatch means discard, with no judgement call and no caveat.
  A coordinator's hold protects one run because someone happened to be listening; a
  recorded hash protects **every** run, including cron workers and unsupervised sessions.

  **And the reframe that came with it: CLAUDE.md's "verify against a known sha" is about
  CAPTURING before the fact, not reporting after.** The coordinator had been honouring it
  as a reporting obligation — naming the sha in messages — which is the weaker half.
  Capture makes a claim checkable by someone who was not there; reporting only makes it
  attributable.

  Applies to pins too: `stable_linux_amd64/**` changing mid-run breaks an A/B **regardless
  of load management**, because both arms then use different compilers and the result looks
  clean. Interleaving equalises CPU; it cannot equalise a toolchain swap.
- **A MEASUREMENT IN FLIGHT IS A LOCK ON THE FILES IT READS.** Found 2026-08-19 when
  frank3 began editing `lib/rtl/sysutils.pas` while a ~20-minute ladder re-run was still
  running against the live tree — some corpus files may have compiled against a half-edited
  RTL. It caught itself, stashed, and declared the run **possibly contaminated** rather
  than reporting it.

  The pin lock is the well-known case of this and it is not the only one. Any long
  measurement — `nilpy_ladder.py`, a corpus sweep, a differential run — reads the working
  tree *while* it runs, so an edit landing mid-run silently mixes two trees into one
  result. **The coordinator's share: do not pin, and do not let a worker start editing
  shared `lib/rtl` or `compiler/**`, while a measurement is known to be in flight.** Ask
  what is running before taking the lock, the same way the lock is announced before it is
  taken.

  And the reporting rule that goes with it, which frank3 got right: **a possibly-
  contaminated measurement is discarded and re-run, never reported with a caveat.** A
  caveated number gets quoted without its caveat — that is the same mechanism as a dated
  table reading as current forever.
- **DISPATCH GOALS, NOT TICKETS — the coordinator is not the queue.** (user, 2026-08-19:
  *"it seems to me the old fashioned way of setting a goal kept agents busier"*, after a
  third check found both workers idle.)

  Handing out one ticket at a time makes every completion park a worker until the next
  hourly check — up to an hour of idle per item, and the coordinator becomes the
  bottleneck. CLAUDE.md already has the self-serve loop (`tools/progress.sh next --track X`
  → claim → do → `resolve` → repeat); inserting a human-speed relay into it is a
  regression, not supervision.

  **Give each worker a standing goal plus the self-dispatch loop, and name the three things
  worth interrupting for: a pin, a genuine fork for the human, a blocker they cannot
  route.** Keep `working/` honest so the lock stays visible. Sequencing *within* lanes a
  worker already holds is the coordinator's to set and should be set once, as an ordering,
  not doled out.

- **BEFORE ESCALATING A FORK, CHECK WHETHER YOU MANUFACTURED IT.** Same day, the
  coordinator raised an ownership fork to the user — should frank3 take two Track N bugs so
  the corpus lever unblocks? — and it was **not a fork at all**: frank2 already held N, the
  tickets were in its own lane, and the real question was only work ORDERING inside lanes it
  already had. The fork existed solely because the question had been framed as "hand them
  to frank3".

  **A fork that dissolves when you change the framing was never the user's to answer.** Ask
  what the decision actually is before asking who owns it: an ownership question that only
  appears because of *your* proposed reassignment is a question about your proposal, not
  about ownership. Escalating it spends the user's attention on a problem you created — and
  the standing reporting mode says their attention is for what genuinely needs them.
- **REPORTING MODE (user, 2026-08-19): surface only what needs the USER.** *"Just tell me
  when a track wants a fresh clear."* So the escalation bar is: a worker needs a fresh
  session, a restart, a permission cleared, or a decision only the human can make (Track U,
  staffing, ownership). Everything else — landings, greens, pins, reds routed to a lane,
  tickets filed, predictions confirmed — goes in this roster and the check log, NOT to the
  user.

  This does NOT relax verification or filing; it narrows who hears about it. Keep verifying
  peer claims before relaying between workers, keep the roster current, keep filing what
  gets measured. The change is the OUTBOUND channel to the human only.

  And note the trap it creates, given this session's own history: a status label is not
  evidence a worker needs clearing (`waiting` means working — four bad escalations came
  from that). Confirm against something that moves before spending one of these.
- **`ListAgents` status labels: `waiting` means WORKING, `idle` means IDLE. Do not invert
  them.** A session shows `waiting` while it is waiting on something it started — a build,
  a tool call — which is what a busy worker looks like most of the time. `idle` is the one
  that means nothing is in flight.

  Cost of getting this backwards on 2026-08-19: the coordinator reported frank3 as "stuck
  on a permission prompt, only the user can clear it" across **four consecutive checks**
  and escalated it to the user each time, while frank3 was working normally and landed
  `7bebd63fa`. The genuinely idle worker (frank2, post-plan, `blocked-by: []`) was reported
  as fine. Both errors in the same glance, in opposite directions.

  **Never diagnose a worker from the status label alone.** It is one bit and it does not
  distinguish "thinking" from "blocked on a prompt". Confirm against something that moves:
  `git log` for its recent commits, `working/` for its lock, or the ticket body for a
  written blocker. If those disagree with the label, believe them. And before escalating
  anything to the user as "only you can clear this", check that it is not simply a worker
  doing its job.
- **PIN AT EVERY CHECK IF `compiler/` OR `lib/` MOVED — pinning is the coordinator's job
  and nothing else surfaces staleness.** Two commands answer it and nothing on the board
  does:

      tail -1 stable_linux_amd64/default/pin.log
      git log --oneline <that-sha>..HEAD -- compiler

  If that lists anything, **pin** (~35s, announce the lock to workers first — it covers
  BUILDS, not just pins). **Use this exact form:**

      set -o pipefail
      make stabilize-fast 2>&1 | tail -5 && make pin 2>&1 | tail -3

  **`set -o pipefail` is LOAD-BEARING, not tidiness.** Without it a pipeline's exit status
  is the LAST command's, so `make stabilize-fast 2>&1 | tail -5 && make pin` runs `make
  pin` even when the build FAILED — `tail` exits 0 regardless. Verified 2026-08-19:
  `false | tail -2 && echo RAN` prints RAN. The coordinator ran that unsound form for
  four pins in one day. It never bit (every run printed `STABLE vNNN OK`), but the failure
  it exposes is **pinning a binary whose self-host fixedpoint did not pass** — the one
  property a bad pin can poison for everyone, and the entire reason the gate exists.

  Caught by frank3, which hit the same chained-exit-status bug in a benchmark harness and
  reported the shape rather than its own instance.

  **Scope, refined 2026-08-19 after the rule cried wolf on its first run:** only
  `compiler/**` matters. `lib/**` alone does NOT need a pin — lib units are compiled from
  source with `-Fu`, so a new `lib/rtl/mimic_*.py` is usable the moment it lands. Only
  `compiler/**` becomes the binary, and only `compiler/builtin/**` is frozen into the pin.
  A rule that fires on `lib/` would hold the repo-wide lock for changes that do not need
  it, which is its own failure — the first check after writing it flagged `7bebd63fa`
  (ElementTree, pure `lib/rtl` + Makefile + docs) as needing a pin. It did not.

  **Why it is safe to do routinely:** every pushed commit already passed
  `make compiler/pascal26`, which IS the byte-identical fixedpoint, so pushed master is
  pinnable by construction. And `make revert` moves `pinned` back, so a bad pin is cheap.
  There is no prudence in waiting.

  **Pin when the workers are IDLE — that is the cheapest window and it is free to spot.**
  The lock's whole cost is contention, so a pin taken while everyone is between items costs
  nobody anything. Corollary: **an idle fleet is a pin opportunity, not just a dispatch
  problem.** Check the pin the moment you notice idleness, before dispatching them back
  into work that will make the lock expensive again. v354 was taken exactly this way.

  **Pinning per-INCREMENT is not churn.** A partially-implemented feature is still a
  gated, self-hosting compiler — increment 1 of p88 passed the fixedpoint like anything
  else. The alternative is B building against a compiler that predates the work, which is
  the failure that actually happened.

  **Why it must be routine and not on demand:** on 2026-08-19 the pin sat a full day stale
  at v352 with twelve compiler/lib commits on top, while `working/`, every `ready` queue
  and tstate all looked healthy — **pin staleness appears in none of them.** It surfaced
  only because the USER noticed a blocked worker. A worker cannot see it either: Track B
  builds with `$(PXX_STABLE)` and simply gets old behaviour, silently. The whole cost of
  the miss lands on the lane least able to diagnose it.

  Corollary already recorded elsewhere and worth repeating here: **a pin blesses
  origin/master.** Unpushed work is not in it — say so when announcing, so a worker holding
  something locally asks for a re-run instead of assuming.

### Open horizon items parked for the week

Three lighthouses (FPC, Linux tinyconfig, MINIX — the last chunked into four separable
goals) and `refactor-a-carve-out-plexer-pparser-so-p-owns-its-own-files` (p60, prio is a
*proposal*: it buys parallelism, not features, and grew a great deal after filing —
rerank it deliberately rather than inheriting the number).

- **frank3: strtofloat, and the biggest cost was not float work** (`df15ae3fe`, lib-test
  green; pinned v352 `0d2087d629bf`, A/B with only `lib/rtl/sysutils.pas` differing, so
  no pin artefact). **Verified here by reading the before/after, not relayed:**
  `TryStrToFloat` called `StrToFloatDef` TWICE with different defaults and compared the
  answers, using disagreement as the failure signal because the parser had no failure
  channel. `StrToFloat` goes through it, so **the whole family parsed every input twice**
  — 1.9-2.0x on every shape. Now one `ParseFloatCore` call.

  Results: fast path **4.7x** (2823→597 ns), 17-digit **2.03x**, subnormal **2.05x**;
  versus CPython the fast path goes 21x slower → 4.4x. **Ticket correctly stays OPEN and
  went back to `backlog/`** — the gate wants an order of magnitude and Eisel-Lemire is
  still the fix (`MulHiU64` already exists in `lib/rtl/wideint.pas`, so the 128-bit
  multiply is not the obstacle).

  **Three lessons, all recorded as a memory:** (1) when a whole family is uniformly slow
  by the same factor across wildly different inputs, **suspect the wrapper, not the
  algorithm** — four passes profiled the float code because that is where the ticket
  pointed; (2) the quadratic append had a **sibling** frank3 did not grep for when it
  fixed the first one in August, costing a second pass — exactly what
  `normalise-dont-special-case` warns about; (3) the title named the wrong axis again
  (not small exponents: `|expo| > 22` in **either** direction, and 16-17 digits falls off
  at exponent **zero** — which is every value `FloatToStrExact(x, 17)` writes).

  **My revision was the right call and worth stating as one:** I told frank3 two hours
  earlier that nothing in B was worth its budget. Looking at the NUMBER (3600x) instead
  of the RANK (p30) is what found a 2x on every `StrToFloat` in the RTL. The standing
  "float bugs are low prio" rule is about *accuracy*, not three-order-of-magnitude
  performance cliffs — and p30 is now *correct*, since the cross-cutting cost has been
  extracted and the remainder genuinely is float work.

- **check 2026-08-18 (+9h):** quiet, nobody blocked. **Track T independently confirms
  frank3's strtofloat landing** — `df15ae3fe1dc` GREEN (native) on plexus, which is a
  second source for the lib-test-green claim rather than the worker's own word. frank2
  still working the subscript-override dispatch (busy, not pinged). `working/` and
  `urgent/` empty — worth noting frank2 has not claimed, so the reminder goes at its next
  natural report rather than as an interruption now. Same single documented false-positive
  red. No dispatch.

- **2026-08-18 night — BOTH WORKERS CLEARED BY THE USER; yield finally dispatched.**
  The one thing the whole day's dispatch discipline was protecting: `yield` goes to a
  FRESH session, and both are now fresh with full budget.

  **frank2-7e (A+N, sole-A) → `feature-nilpy-yield-outside-a-for-loop` (p75).** The
  week's bet: 18 of the 32 remaining language walls, more than every missing-module
  blocker combined. Briefed self-contained (a cleared session remembers nothing), pointed
  at the four load-bearing sections of the 494-line ticket rather than the whole thing,
  and warned about three things: **(1) the ticket contradicts itself** — a section near
  line 252 says it depends on the pending boxed-def decision at step 4, and a later one
  near 345 says re-measure that before believing it; the stale half comes FIRST, so a
  fresh reader hits it and may stop wrongly. **(2)** do not start boxed-def option B
  speculatively. **(3)** the failure mode is silent stack corruption in
  `PyEmitParamSpills`, so measure rather than reason. Told to bank-and-park in
  `unfinished/` rather than half-land a Track A change.

  **frank3-fc (B) → `feature-b-mimic-urllib-request-over-the-rtl-http-stack` (p30).**
  Best available in B. Briefed on the pin boundary, on the file being a *present-and-
  refusing stub* (its existence is the ticket's premise, not evidence of completion), and
  on `mimic_codecs.pas` as the established pattern to follow rather than inventing a
  second one. Told the single corpus caller is a code generator, so nothing is blocked —
  aim for an honest surface, refuse loudly where the RTL cannot back the real API.

  **Note for the next coordinator session:** that self-contradiction inside the yield
  ticket is worth fixing properly once the work settles — marking the superseded section
  as superseded, in place, the way Track T banner-corrected its own closed timeout ticket.
  Not doing it mid-flight while a worker is reading the file.

- **check 2026-08-18 (+10h):** both workers BUSY on their dispatches (frank2 = yield,
  frank3 = urlopen), no commits yet, nothing blocked, not pinged. T UP; full tier caught
  up to `df15ae3fe1dc` with the same single documented `crtl_exp2` false positive as its
  only red. `working/` still empty while both work — the claim reminder is deliberately
  HELD for their next natural report rather than interrupting active work on the week's
  highest-value ticket. No dispatch, nothing invented.

- **check 2026-08-18 (+11h) — YIELD LANDED. The week's bet, resolved in one evening.**
  `feature-nilpy-yield-outside-a-for-loop` is in `done/` across four commits
  (`c59a57ff4` generators consumed by for-in → `1d84a4bef` generator METHODS, "the shape
  the html5lib filters are made of" → `78842fec8` 6 parameters not 4 → `f132f1f7e` the
  Pascal `var` fix). frank3 also landed `5a900c598` — a real `urlopen` over
  `lib/rtl/http.pas`.

  **frank2's own honest scoring, which is the part to keep:** all three yield-walled files
  compile and **`yield` is no longer any file's wall** — but the html5lib count is
  **unchanged at 7 of 33**, because the parameter lift moved three treewalkers onto their
  NEXT wall. Its phrase: *"progress-shaped without being progress."* That is exactly the
  past-a-wall / onto-the-next-wall discipline applied against its own result.
  **Denominator caution for whoever reports upward: 7/33 is html5lib alone; the 6/48
  figure used earlier today is the full ladder (html5lib + tinycss2 + webencodings). Do
  not conflate them.**

  **The banked plan was right about the engine, the strategy and the disproven Track U
  dependency — and wrong about the crash site:** it was the EPILOGUE releasing the
  generator's live state, not the prologue spills. Worth remembering the next time a
  banked diagnosis is handed to a fresh session: it bought the strategy, not the bug.

  Two gaps filed rather than left: `feature-nilpy-a-generator-as-a-first-class-value`
  (p55 — `g = gen()`, `list(gen())`, `next(g)`; compile errors today, which is the right
  failure mode and must stay one) and
  `bug-nilpy-a-generator-instance-leaks-its-locals-and-argument-cells` (p40 — the
  deliberate trade behind the epilogue fix, with the ordering constraint that makes a
  naive fix re-create the dangling pointer).

  **Open red triaged, not left to trap someone:**
  `test-core#src:test/test_stackless_gen.pas` is very likely ALREADY FIXED — `f132f1f7e`
  names it and claims a verified green, and T's latest run at `78842fec8beb` predates that
  commit. Annotated the ticket "do not start, re-verify at HEAD or wait for T's next run".
  Deliberately did NOT build to confirm, because frank2 still holds the tree and a
  concurrent `make` is a collision. Its root cause is another **identity-vs-kind** case:
  the variant cell keyed on `Params[k].IsRef`, true of both a Pascal `var` param and a
  generator's by-ref `const record`, so a Pascal generator was told it needed pylib's
  `pycell_new`. The watcher's `track: P` guess is wrong (fix is in `parser.inc` = A).

- **check 2026-08-19 (00:xx) — triage confirmed, and the check prompt itself was fixed.**
  Track T reports **`FIXED: test-core#src:test/test_stackless_gen.pas`** at
  `18bcb92ffb8b` and auto-closed the regression — my "already fixed by `f132f1f7e`, do not
  start on it" annotation was right, and not building to confirm (frank2 held the tree)
  cost nothing but an hour. The generator work also cleared **slow GREEN, opt GREEN and
  bench ok** on the full matrix; the only remaining red is the documented `crtl_exp2`
  false positive. **So yield landed AND survived the full cross-target sweep.**

  **The hourly cron prompt carried a durable fact that had become FALSE** — it still said
  yield was scheduled-not-queue work reserved for a fresh session, hours after it landed
  in `done/`. Exactly the hazard the prompt itself warns about, in the prompt itself.
  Replaced (job `9108876a` → `acbdd5c1`, same :23 schedule). What changed:
  - the yield entry is **gone**, replaced by a pointer to the STANDING MANDATE section at
    the end of this file — so the charter lives in one place that can be edited, rather
    than being copied into a prompt that cannot self-correct;
  - added **"read `ready` for EVERY staffed lane"**, the failure that hid Track A's p55
    FreeBSD ticket for a day;
  - added the two-claims pin rule, "a title names the encounter not the boundary", "the
    file exists ≠ the work is done", "never build while a worker holds the tree", and the
    `crtl_exp2` false-positive shape with its re-prove-if-the-pin-moved caveat;
  - dropped the hardcoded 6/48 figure in favour of "re-measure, never quote a scan".

  **Lesson for whoever maintains that prompt: a durable fact with a subject that can be
  COMPLETED is not durable.** Point at a file for anything that can finish; reserve the
  prompt for rules that stay true. Both workers idle/quiet, nothing blocked, no dispatch.

- **check 2026-08-19 (+1h): both idle after landing, so both re-dispatched** — the user
  cleared them explicitly to run overnight, and idling capacity the user is paying for was
  the wrong call once already today. Read all four staffed lanes first, per the standing
  rule.

  **frank2 (A+N) → `feature-nilpy-a-generator-as-a-first-class-value` (p55).** It filed
  this itself an hour ago as the gap yield does not cover (`g = gen()`, `list(gen())`,
  `next(g)`, `__iter__`), so it holds maximum context. Told to preserve its own judgement
  that these are compile errors today and **that is the right failure mode** — prefer the
  compile error over an intermediate state that compiles and then yields nothing silently,
  which is the shape the epilogue crash just demonstrated. The p40 leak ticket stays
  parked unless it lands on the critical path; its recorded ordering constraint (a naive
  fix re-creates the dangling pointer) is to be respected, not routed around.

  **frank3 (B) → the Eisel-Lemire half of the strtofloat ticket (p30).** Its own parked
  work, with its own datum: `MulHiU64` already exists in `lib/rtl/wideint.pas`, so the
  128-bit multiply is not the obstacle and the job is the power-of-ten table plus
  decline-and-defer. Told `lib_strtofloat_roundtrip` must stay green (it is the sweep
  frank3 landed in August precisely so a perf change cannot silently trade away correct
  rounding, and it caught something last pass), to measure on the PIN not HEAD, and to
  bank-and-park rather than land a half-converted parser — a float parser fast on the
  common path and subtly wrong on the decline path is worse than a slow correct one.
  **Explicitly offered the option to decline** at this hour; below this, B is p20 ULP work
  that is not worth a session, and a tired half-landing is worse than an idle night.

- **check 2026-08-19 (+2h) — a very productive hour; both landed, both re-dispatched.**
  T confirms GREEN native through `9cc61eee29c8`.

  **frank2 (N/A), three commits:** `091728229` a generator is a first-class value,
  `8e540be59` an object whose `__iter__` yields is iterable, `9cc61eee2` **a generator
  for-in inside a block swallowed the statement after it** — that last one silent, and the
  kind that gets blamed on anything but the loop. Ticket resolved to `done/`; it also
  banked "the two wrong designs" it tried, which is the expensive half of a write-up and
  usually the half that gets dropped.

  **frank3 (B): Eisel-Lemire landed** (`a4c1bf31d`) — **27x to 1118x** outside Clinger's
  window, over a 696-entry truncated-powers-of-ten table, with `MulHiU64` supplying the
  high half exactly as its own previous pass predicted. The safety argument is the
  load-bearing part: **Lemire DECLINES rather than guesses**, `ExDecNearest` is untouched
  and still answers everything Lemire will not, so the residue is correctly rounded *by
  construction* — which is what makes it safe to bolt a fast path in front of an exact
  parser.

  **The honest half, and it is the reusable lesson: the two rows the ticket NAMED did not
  move.** "small" (1e-310) and "subnormal" (1e-320) are both subnormal, where Lemire
  declines below the normal floor by construction — Go and Rust decline there too. A less
  careful pass would have led with 1118x and let the headline rows quietly stay slow.
  frank3 rescoped the remainder as **a rewrite of `ExDecNearest` in binary big-integer
  arithmetic, not an extension of Lemire**, which saves the next person from stretching
  Lemire somewhere it cannot go. Third or fourth instance in two days of *a title naming
  the encounter, not the boundary*. Also kept visible rather than rounded away: the
  Clinger fast path came out **5% slower** on code layout, and that is the path most
  inputs take.

  **Dispatched frank2 → RE-MEASURE THE LADDER** (`tools/nilpy_ladder.py`), because that is
  the standing mandate's own question and tonight's four generator commits are exactly
  what should move it. Told to name the sha, split past-a-wall from onto-the-next-wall,
  keep the 7/33 (html5lib) and 6/48 (full ladder) denominators distinct, quote no earlier
  scan, and then **follow the measurement rather than the backlog ranking** — including
  "the walls are diffuse" as a legitimate finding to report and stop on.
  **frank3 → offered the rescoped ExDecNearest rewrite or a clean stop, its call**; a
  big-integer comparison rewrite is not obviously a small-hours job and two landings is a
  good night.

- **check 2026-08-19 (+3h): no new work commits; one new signal, isolated and routed.**
  frank2 busy (ladder re-measure, no commits yet — not pinged); frank3 idle, no reply to
  the take-it-or-stop offer, which is a fine answer at this hour. `working/`/`urgent/`
  empty.

  **Track T's bench run went RED at `9cc61eee29c8` — 27 rows where the previous run was
  "ok" with 30.** A row-count drop is a failure to PRODUCE a measurement, not a slow one,
  so it is a different animal from this repo's two previous bench reds (both timing
  artefacts: co-tenancy, p-state quantisation). Diffed the row sets by benchmark name:

  ```
  fib 4  mandelbrot 3  mandelbrot-p 4  nbody 4  raytracer 3  raytracer-p 4  sieve 4
      -- all IDENTICAL across both runs
  selfcompile:  4 rows before  ->  1 row now
  ```

  **The entire delta is `selfcompile` losing 3 of 4 variants.** Routed to plexus-T
  (bench tooling is T's, and T owns the tool) with the counter-evidence it needs rather
  than a theory: selfcompile is precisely what the per-fix gate proves, and every commit
  in that window landed through `make compiler/pascal26` — the byte-identical fixedpoint —
  plus `gate.sh quick`. Four generator commits and a float parser all passed it, so the
  compiler demonstrably self-compiles at those shas, which points at the harness rather
  than at the thing it measures. **No ticket filed by me:** T's tool, T's call, and T has
  run detail I do not.

  Full tier at the same sha re-checked properly rather than assumed: `new_red: []`,
  `still_red: [crtl_exp2]` — the documented false positive, and T's own correction banner
  on the timeout ticket was read first rather than reasoning from the superseded rule.

- **THE BENCH RED WAS A REAL COMPILER BUG, and it broke a piece of reasoning I had been
  leaning on.** plexus-T settled it before closing: `bug-a-self-compile-at-o0-overflows-
  the-code-buffer` (A, **p60**, now top of A). Reproduced outside the harness in one line:

  ```
  make compiler/pascal26                                 -> OK
  ./compiler/pascal26 -O0 compiler/compiler.pas /tmp/x   -> pascal26:170295: error: code overflow
  ```

  **My counter-evidence was TRUE and could not speak to the case.** I argued the bench red
  could not be a compiler problem because every commit in the window passed the fixedpoint.
  But `make compiler/pascal26` builds at the **DEFAULT** level and the fixedpoint proves
  byte-identity **at that level** — nothing in the per-fix loop and no T tier compiles
  `compiler.pas` at `-O0`. So **passing the self-host gate is evidence that the compiler
  compiles itself at ONE optimisation level, not that it compiles itself.** Week's
  recurring shape again: a correct, checkable fact standing in for the deciding one. Now a
  memory.

  **Also one defect presenting as three:** `-O2`/`-O3` reported `CANARY-DIFF vs -O0` only
  because the canary compares against a `-O0` build that did not exist, and `fpc` survived
  because it uses FPC. Three red rows, one cause — told frank2 so it does not hunt three.

  **The diagnostic that found it is worth keeping:** a **row-count drop is a failure to
  produce a measurement; a slow row is a failure of the box.** Both previous bench reds
  here were timing artefacts, so the trained instinct is to dismiss a bench red — missing
  rows point at the SUBJECT, slow rows at the ENVIRONMENT. Diffing row sets by name
  isolated the whole delta in one step.

  **Routed, not actioned:** the ticket goes to frank2 (sole-A) **after** its ladder
  re-measure — told explicitly not to context-switch mid-measurement. The gate-policy
  question T raised is filed as
  `decide-should-the-gate-prove-self-compile-at-more-than-one-o-level` (U, p55) rather
  than settled here, because gating policy is not the coordinator's to change; my
  recommendation in it is a **Track T tier, NOT the per-fix loop**, since the loop's
  shortness is load-bearing and hard-won. Regardless of that outcome, `CLAUDE.md`'s
  claims-discipline section should note that "self-host fixedpoint" means *at the default
  level* — the phrase is used as evidence of general soundness and is scoped narrower than
  it reads.

  plexus-T's session is closed; Track T is unstaffed until the user restarts it.

- **check 2026-08-19 (+4h): two landings, a proper claim, and the bench is green again.**
  T reports `185575980d53` GREEN native/slow/opt and **bench back to ok (30 rows)** —
  independent confirmation the selfcompile rows returned. `working/` now holds
  `bug-nilpy-a-callable-in-a-variable-loses-to-a-def-of-the-same-name`, so frank2 is using
  the lock; no reminder needed.

  **The `-O0` fix (`6b2402b92`) was root-cause, not microfix, and the measurement inverts
  the ticket.** It was never an `-O0` problem:

  ```
  -O2/default 7 415 348 B   -O1 7 458 182 B   -O3 7 561 519 B   -O0 8 394 698 B
  ```

  **All four levels sat at 88-90% of the 8 MB cap.** `-O0` was first across a line every
  level was standing on, and **ordinary growth would have taken the DEFAULT build down
  next.** Cap now 16 MB, default at 44%; cost is virtual BSS only. The error message now
  names the cap and the inversion that made it confusing — **lower `-O` levels emit MORE
  code, so a build that fits at `-O2` can still overflow at `-O0`.**

  I updated `decide-should-the-gate-prove-self-compile-at-more-than-one-o-level` with this,
  because it materially strengthens one side of a ticket I wrote: `-O0` was not merely
  covering a blind spot, it was a **leading indicator** of a condition about to break the
  level the gate does check. A check that fails first and cheaply on a shared underlying
  condition is worth more than its own coverage. **Recommendation unchanged** (T tier, not
  the per-fix loop) — a leading indicator works just as well run asynchronously.

  **THE LADDER WAS RE-MEASURED — at `594bd3c8c`: 12 of the 38 remaining failures share ONE
  root cause, and it is a silent-wrong-function bug, not a missing feature.** Filed and
  claimed as `bug-nilpy-a-callable-in-a-variable-loses-to-a-def-of-the-same-name` — the
  new top wall, and the same concentrated shape `yield` had. **Denominator caution: "38
  remaining failures" is frank2's figure on the full ladder at that sha; do not reconcile
  it against the older 6/48 or 7/33 by arithmetic — ask for the headline when it reports.**
- **checks 2026-08-19 (+5h, +6h):** quiet, nobody blocked, no commits. frank2 still holds
  `bug-nilpy-a-callable-in-a-variable-loses-to-a-def-of-the-same-name` in `working/` and is
  busy — ~2h without a commit is unremarkable for a root-cause hunt on a silent
  wrong-function bug spanning 12 files, and it is not pinged. frank3 stopped on the offer
  made at 01:30. T UP, same documented false positive. Track T remains UNSTAFFED since
  plexus-T closed.
- **check 2026-08-19 (+7h, morning):** quiet, nobody blocked, no commits. **Track T is
  RUNNING again** (plexus-T back from unstaffed — the user flagged its old session was at
  910k and needed fresh context). Not pinged; it is busy and will report or publish tstate
  on its own. frank2 still holds the top-wall ticket in `working/`; frank3 still stopped.
  **No dispatch: the user explicitly said not to start any jobs pending the way-forward
  discussion.** Reported the night to the user, and corrected the alarm they woke to — the
  `-O0` self-compile failure was already FIXED (`6b2402b92`, ticket in `done/`, T's bench
  back to 4 `selfcompile` rows at `185575980d53`), and it was never an `-O0` problem: all
  four levels sat at 88-90% of the cap and the DEFAULT build was next.

- **check 2026-08-19 (morning, +8h): decisions worked, and the check prompt fixed AGAIN
  for the same reason.**

  **Six decisions answered by the user this morning, all recorded, moved to `decided/`,
  and — critically — RE-FILED as work**, since `ready`/`next` do not read decisions:
  boxed-def → `feature-n-a-callable-value-carries-its-signature-type` (A, **p88**, top of
  A); ElementTree → `feature-b-mimic-xml-etree-elementtree-tree-model` (B, p62);
  `-O` differential → `feature-t-tier-job-self-compile-differential-across-o-levels`
  (T, p55); unwired tests → `chore-a-sweep-the-unwired-tests-into-the-suite` (A, p55);
  MINIX → **deferred to `rainy-day/`** with its version fork withdrawn alongside it.

  **The user corrected me on the unwired-test sweep and the correction generalises:** I
  filed it under Track T, and T is bound by *"T owns the tool, never the bug"* — so under
  T **every red must become a ticket for another lane**, which across ~61 files is a
  ticket factory. Under A, which can fix a red in place, the identical job is a **sweep**.
  **The lane choice, not the method, decides whether something is one job or sixty-one.**
  Now a durable fact in the check prompt.

  **Stale durable fact, second instance, same class.** The prompt still said the boxed-def
  decision "is with the human, do not decide it" — hours after the user decided it. I had
  already recorded the lesson (*a durable fact whose subject can COMPLETE is not durable*)
  and then left exactly such an item in. Prompt rebuilt (`acbdd5c1` → `a442fa26`): the
  boxed-def entry is gone, and the rule about finishable subjects is now stated **in** the
  prompt so the next rebuild does not repeat it. Also added: re-file decided work, the
  lane-choice rule, the default-`-O`-only scope of the fixedpoint claim, and that a worker
  showing **"waiting"** may be stuck on a permission prompt only the USER can clear.

  **State:** frank2 landed `9ffc1637f` (backslash-newline line continuation) and is
  between items — nudged back to the fruit list, and told the p88 now outranks it with the
  settled design summarised so it needs no re-deriving. **frank3 shows "waiting", which is
  NOT idle — surfaced to the user as possibly a permission prompt.** Track T is active on
  its own tooling (`c99f15692` a job whose measured duration passed its class budget could
  never pass; `e96a60c07` est_mem below what lib-test#00 actually peaks at). T green
  through `c99f1569246d`.

- **check 2026-08-19 (+9h): U queue emptied, a new red routed, frank3 still stuck.**

  **Track U is now EMPTY.** The last four went today, and three of them had already
  answered themselves and were sitting in `backlog/` looking open — `decide-unary-minus`
  (user caught it), `decide-what-synapse-actually-needs-vs-mimic-fpc` (user caught it),
  and `decide-nilpy-exec-injects-a-builtins-key` (partly). All recorded, moved to
  `decided/`, and **re-filed as work**: unary-minus → `bug-p-unary-minus-…` (P, 30→45);
  identity → `refactor-a-one-resolved-file-identity-for-a-translation-unit` (A, p45);
  `__builtins__` → parked in `rainy-day/` + a Track D docs ticket (p40).

  **My self-amendment grep missed two of the three.** I searched for phrases ("already
  settles this", "is a confirmation"); Synapse announces itself with a `DEPRIORITISED`
  blockquote instead. The pattern is not a phrase — it is **a decision recorded inside a
  ticket that stayed in the ready queue** — and I have no reliable detector for it. Worth
  a Track T tooling idea if one ever wants filing hygiene automated; not filed, because it
  is my failure mode and not obviously anyone's ticket.

  **A superseded root cause propagated into a DECIDED ticket, same day, and the user's
  unrelated question is what caught it.** I described the C double-compile bugs as
  "include-guard visibility lost across a macro-table reset" — that ticket's TITLE and
  opening section, superseded by its own 2026-08-16 measurement (carrying the macro table
  leaves output byte-identical; forcing the guard on breaks the pull). Real cause:
  `stdarg.h` carries six `static` function BODIES and the crtl auto-pull must include it —
  **Track C library work**, not preprocessor or `parser.inc`. Corrected in three places
  plus the ticket's frontmatter `summary`, since that is what the board renders, and a
  banner above its body where a searcher lands. Title kept so search terms still work.
  **On a long-lived ticket the title and summary are the OLDEST prose in the file and the
  only parts rendered — read the LAST dated section first.**

  Also settled while there, since it recurs: the C reset is **not a regression**.
  `CPMCount := 0` shipped in `4c21e86eb` (2026-05-26), the commit that introduced the C
  preprocessor, alongside the Pascal-`uses`-a-`.c` invocation site. Pascal define scoping
  never narrowed anything for C; `147087b0c` (2026-07-07) added a third invocation and
  made a day-one latent bug visible. "Was it always broken?" is answered by `git log -S`
  on the line, not by narrative.

  **Convention stated (2 instances, not enough for process):** a closed ticket whose text
  asserts an incomplete design gets a **correction banner above its body naming the live
  ticket** — never reopened. `done/` records what a session shipped and rewriting it
  falsifies history. Applied to `feature-mimic-fpc` (claims the scoped manifest is primary;
  only the fallback shipped → `feature-dynamic-include-paths-config`, whose **Synapse
  justification is now withdrawn** — rank it on self-build safety instead).

  **T: NEW-RED `lib-test#src:test/lib_tls.pas`** at `6070883b46e7` (31 in range), and
  `crtl_exp2.c` FIXED — the documented false positive is off the board. Routed to plexus-T
  rather than bisected: the job does a **real loopback socket round-trip**, its 2026-08-16
  instance was not reproducible natively and auto-closed green, and the open question from
  that triage — transient vs host-specific — is answerable only on plexus. Asked it to
  hold the 31-commit bisect until that fork is settled, and flagged that no NEW-RED stub
  appears to have been filed.

  **Dispatch:** frank2 idle → `feature-n-a-callable-value-carries-its-signature-type`
  (A, p88, the settled boxed-def design), with the observation that N's top item
  `bug-n-a-call-through-a-callable-value-drops-the-callees-defaults` (p70) is probably the
  **same gap** and may be subsumed — asked it to check the relationship before cutting,
  since it changes how N ranks behind it. Told it to make `working/` say whether the
  unwired-test sweep is active or parked. Deliberately did NOT also hand it Track C's p55.

  **frank3 has shown "waiting" since the morning check — that is USER-CLEARABLE only**
  (likely a permission prompt), and Track B has ready work at the top (`feature-b-mimic-xml-
  etree-elementtree-tree-model`, p62). Surfaced again; this is the second check in a row.

  **Track C staffing (`decide-staff-track-c-…`, the last U item) is with the user.** My
  recommendation: no standing 4th checkout — three sessions is the compile-stream limit on
  an 8-core box and C's queue does not justify a permanent seat; dispatch its p55 per-ticket
  to whichever frontend session frees up. Not settled here — staffing is never the
  coordinator's call.

- **check 2026-08-19 (+10h): T settled lib_tls with a FOURTH answer, and found a filing
  bug that had silently disabled 182 jobs.**

  **lib_tls is neither a regression nor transient — the TEST is defective.** plexus-T
  refused all three options I framed and produced a better one, with an 8-second repro.
  `test/lib_tls.pas:69` hardcodes `PORT = 28755` and lines 96-107 ignore the return of
  every socket call — no `SO_REUSEADDR`, no timeout. **Verified here:** the const is there
  and `fpBind`/`fpListen`/`fpConnect`/`fpAccept` are all called bare. Two concurrent runs
  and one of them hangs forever at 7 of 14 `=ok` — the TLS seam the test exists to check
  is never reached. plexus is simply the box where two clones run testmgr by design, so a
  fixed port is a shared global there.

  **The measurement that beat my framing:** solo re-runs are all green at 1.0s against a
  90s budget, which reads as "transient, close it" — and the prior 2026-08-16 triage
  stopped exactly there. But EWMA 45.4s over n=46 on the watcher clone vs 2.4s over n=16
  in the dev clone says otherwise: **a one-second test does not average forty-five seconds
  by being slow.** A timeout on a 1s test is a HANG, not slowness. Worth keeping as a
  diagnostic — mean-vs-solo divergence distinguishes a hang from a slow box.

  Also decidable rather than judgement: lib_tls is `pin_built`, and nothing it reads
  changed across the 31-commit range (no `lib/**`, no `test/lib_tls.pas`, no
  `stable_linux_amd64/**`). The watcher's own `pin_immune()` had already refused the
  bisect. Filed **Track B** (`bug-b-lib-tls-hangs-forever-when-its-hardcoded-port-is-
  unavailable`, p55) per "a test fix belongs to the lane owning the test", with siblings
  flagged (`lib_mimic_urllib_request_server` takes 28901 on the command line;
  `lib_http`/`lib_http_async` unaudited neighbours).

  **THE OPERATIONAL ITEM — a resolved ticket permanently disabled its job's future
  filing.** My "no stub was filed" point was right and the cause is worse than a missed
  auto-file: `already_filed()` scanned **every** bucket including `done/` and `rejected/`,
  so a job became unticketable FOREVER once its first regression ticket resolved — **182
  resolved `regression-*` slugs against 0 open ones = 182 jobs in that state**, failing
  silently (the loop just continued, printing neither "auto-filed" nor "NOT filing").
  Fixed in `c45ed0062` (recurrences get `<base>-2`, suppression keys on OPEN buckets only,
  refiling announces itself, runaway guard at 20).

  **CARRY THIS UNTIL IT CLEARS: the fix needs a daemon restart, the watcher is mid-full-
  tier, so the NEXT new red still will not auto-file.** Until a restart lands, treat T's
  RED reports as the only filing channel and do not read "no ticket appeared" as "no
  finding". Ask at the next check whether the restart happened.

  The sharpest detail, worth remembering as a class: `regression-lib-test-lib-tls` closed
  saying *"reopening is by a fresh NEW-RED stub"* — **closing that ticket is the act that
  disabled the behaviour it promised.** And the correct reasoning already existed one
  function away in `stub_sources()`, whose comment reaffirmed the wrong parenthesis.

  Also from T: `crtl_exp2` is off the board for a real reason, not a lucky run — its EWMA
  had passed the unit-class budget and the formula kept the class figure as a ceiling over
  a measured job, so it was killed at 90s every time (`c99f15692`). **The inversion that
  hid it three days: only a PEER CLONE's run stretches a budget, so it passed when the box
  was SHARED and failed when it had the box to ITSELF.** Two more filed rather than
  mentioned: `chore-t-five-tool-devtests-are-broken-on-master-and-nothing-runs-them`
  (28 pass / 5 fail on a clean tree, all pre-existing) and `chore-t-unit-class-est-mem-…`.

  **frank2 answered the p88/p70 question and it was worth asking** (`352a52b4b`): **p70 IS
  p88**, confirmed by measurement not by reading — there is nothing to fill defaults from,
  so p70 needs no separate work and N's queue re-ranks with it removed rather than sitting
  behind it. It also found the plan as written names only ONE of **TWO callable
  representations** — cf. the standing memory that callables have three; worth checking
  which count is current. It parked the unwired-test sweep properly (`d05e3657f`, batch 1
  landed, judgement half remains) and `working/` now correctly holds only p88.

  **frank3 still `waiting` — third consecutive check.** Track B now has TWO ready items at
  p55+ (the new lib_tls bug, and the ElementTree shim at p62) and nobody able to take them.
  This is the one thing blocked on the user.

- **PIN v353 (2026-08-19 08:29Z, coordinator).** `256183a5f52c` (was v352 `0d2087d629bf`)
  at `8a16663c6ffe`, commit `0c189b6f0`. Ran on the user's word that frank2 was waiting on
  it; announced the lock to frank2 first, held builds, released after.

  **The pin was a full day stale** — v352 dated 2026-08-18 11:15 with twelve compiler/lib
  commits on top. Worth noting as a coordinator failure mode: nothing surfaces pin
  staleness. `working/`, `ready` and tstate all looked healthy while Track B's ground sat a
  day behind HEAD, and it took the USER noticing a blocked worker. **Check `pin.log`'s
  tail against `git log -- compiler lib` at each check** — it is two commands and nothing
  else answers the question.

  Blessed onto B's ground: the NilPy generator series, `6b2402b92` (code buffer off 88% of
  cap at every -O level), `9ffc1637f` (backslash-newline continuation), `a4c1bf31d` +
  `df15ae3fe` (StrToFloat: Eisel-Lemire and the double-parse fix), `5a900c598` (real
  `urlopen`). Fixedpoint clean at all three rungs, 7415819B / 2899 procs — **default -O
  level only**, as always.

  Told frank2 explicitly that a pin blesses origin/master, so unpushed work is not in it,
  and to say so immediately if it needed a re-run. p88 is NOT in this pin; frank2's last
  commit is the reconnaissance.

- **Track C now has a SPEC, not a discussion** (`40a0a9fb7`). The user designed
  Pascal-into-C importing across a long exchange and it is filed as
  `feature-c-import-a-pascal-unit-under-a-mangled-name` (C, p50), blocked-by the p55
  definition-overwrite bug so the ordering is tooling-enforced rather than prose.

  Settled: `#include "math.pas"` as the import site (fails loudly under gcc — a pragma
  would be silently ignored, the worst shape); `math_pas_Sqrt` with **case preserved from
  the Pascal declaration**, which is what makes the mangled name unable to collide with C's
  `sqrt` and retires the documented infinite-recursion hazard structurally;
  path-qualified on collision; **overloads resolved by the declared C prototype** — the
  user dissolved that fork rather than answering it, since the C declaration already
  carries unit, routine and signature; `AnsiString`-bearing signatures refused by name,
  with `const AnsiString` recorded as a future opt-in and deliberately NOT built.

  The user's hinge, kept verbatim in the ticket because the design is incoherent without
  it: **case sensitivity gives distinguishability, mangling gives identity.**

  Left as an EXPERIMENT rather than a decision: whether implicit cross-namespace binding
  goes away. `cparser.inc:9448` defends it with lua's `<math.h>`, but `lib/crtl/src/math.c`
  now DEFINES exp/log/sin/cos/atan/sqrt in C. Settle it by deleting the bind and building
  lua/tcc/quickjs/zlib — the failures ARE the spec. **Flagged, not concluded.**

  **Three stale "must stay" justifications surfaced in one day** — this one, `stdarg.h`'s
  macro-reset story, and `feature-mimic-fpc`'s scoped manifest. The prior on a confident
  old comment is lower than it looks; check the code it describes before building on it.

- **check 2026-08-19 (+11h): both workers busy, nothing blocked, T green, no pin needed.**
  frank2 on p88 (`working/` holds it), frank3 on the lib_tls p55 after landing
  `7bebd63fa`. T UP: native GREEN through `6d95bd731bce`, full GREEN through
  `c45ed0062491` — **no open regressions at all**, and `crtl_exp2` is genuinely fixed
  (`c99f15692`) rather than merely quiet. Pin check ran and correctly said no: the only
  post-pin commit is `lib/rtl` + Makefile + docs.

  **frank2 corrected my count and it matters** (`70f7070ba`). I told it there were THREE
  callable representations, citing a standing memory (9/10/12). `defs.inc` says **FOUR** —
  `VT_BOUNDMETHOD` = 8 is missing from the memory AND from frank2's own first answer of
  two, **and it is the tag `PyMakeFuncValueFor` stamps via `pybound_new`, i.e. the path
  this ticket's own headline repro takes.** A design changing only tag 12 and TPyClosure
  would have left the primary repro broken. It also scoped out `VT_CLASSREF` = 11
  (invoked, but its callee is a ctor) by NAME rather than leaving it to be re-derived, and
  confirmed nothing was retired — 9 and 10 are deliberately distinct and `defs.inc` states
  why.

  **The lesson is about me, not the number: I handed a worker a count from recollection.**
  A count is exactly the kind of fact that goes stale silently, and the memory that carried
  it was written when three was right. Now a durable rule in the check prompt: never hand a
  worker a count from memory — tell it to enumerate from the source. The worker doing that
  unprompted, and publishing the correction against its own earlier number, is the reason
  this cost nothing.

  **Check prompt rebuilt** (`a442fa26` → `5126e982`), for the third time and the same
  class of reason: it still carried *"a worker showing waiting may be stuck on a permission
  prompt only the USER can clear"* — the inverted rule that produced four bad escalations
  an hour earlier. Also folded in: the pin check as step 2 (scoped to `compiler/**`), the
  read-the-last-dated-section-first rule, the corrected `crtl_exp2` status (fixed, so a new
  red there is real and not the old ghost), and the counts-go-stale rule above.

- **frank3: lib_tls + TEN siblings (`7447bb59a`), and one pair that could collide inside a
  single run.** Verified here: 11 test files, `lib/rtl/asyncnet.pas`, the Makefile.

  Fixed as T diagnosed — reproduced first, then port 0 + `fpGetSockName`, every socket
  return read (14 `=ok` → 16), `fpSelect(5000)` gating the accept. `SO_REUSEADDR` set too,
  but against TIME_WAIT, not as the fix: **REUSEADDR makes the collision rarer, port 0
  makes it unrepresentable.**

  **The audit found NINE more where I had flagged three**, every one the identical shape —
  `lfd := TcpListen(PORT)` with the return ignored and `TcpAccept(lfd)` on the next line.
  **And `lib_http_async` held 28755, the SAME number as `lib_tls`, in the same lib-test
  recipe block** — the one pair that could collide *within a single run* rather than only
  across clones, and neither side knew. frank3 nearly missed it because it searched for
  "hardcoded ports" when the killer was "**duplicate** hardcoded ports". Now recorded in
  the source at `test/lib_http_async.pas:10`.

  **VERIFIED BY CONCURRENCY, NOT BY A GREEN RUN**, and this is the transferable part: the
  OLD test passed solo five times running, so a single green proved nothing. 8 concurrent
  copies of the new one → 16/16; all 11 binaries × 4 copies → zero failures. **When the
  defect IS concurrency, the test for the fix has to be concurrent.**

  Two more things done right rather than fast. `TcpListen` was never the bug — it already
  set REUSEADDR and already returned `rc<0` on a failed bind; **the tests ignored it.**
  What was missing was any way to LEARN which port a port-0 bind got, so the async family
  could not use port 0 at all — hence `TcpLocalPort(fd)` in `asyncnet.pas`, one addition
  instead of eleven workarounds. And `lib_dns_async` was **filed, not ridden along**
  (`bug-b-lib-dns-async-…`, p45): same class, but six fixtures and a UDP/PAL shape the
  other ten do not share, so it would have gone onto their gate unverified. Note its own
  wrinkle — `rc :=` on every `PalBindIpv4`, never read, which **skims as "checked" and is
  therefore worse than not assigning at all.**

  The ticket also records which files are ALREADY clean (`lib_http` opens no socket;
  `lib_ipv6`/`lib_asyncnet6`/`lib_platform_net`/`lib_platform_net_udp` check their binds;
  `lib_net`/`lib_netconnect`/`lib_net_timeout`/`lib_net_v6only` already use port 0 — where
  the idiom came from), so nobody re-audits eight files to learn nothing. Relayed to
  plexus-T with a falsifiable prediction: the watcher's 45.4s EWMA on this job should
  converge toward ~1s, and if it does not, `lib_dns_async` is next.

- **check 2026-08-19 (+12h): ZERO open regressions, and v353 qualifies as a fully-green
  pin — the first in a while.** plexus-T confirmed the EWMA prediction *with a rate*, which
  is the part that makes it falsifiable: 45.37s over n=46 → **11.2s over n=49** on the
  watcher clone, matching the 0.4-alpha curve from 45.4 toward ~1.2 almost exactly
  (predicted 27.7 → 17.1 → 10.7; measured 11.2). Dev clone independently 2.42s over n=16 →
  1.14s over n=21, so the ~1.1-1.2s asymptote is confirmed from two stores sharing nothing
  but the box.

  **The horizon T volunteered, and it is the right way to hand over a prediction:** each
  further full-tier run multiplies the gap to ~1.2 by 0.6 — expect ~7.2, ~4.8, ~3.3, ~2.4,
  ~1.9. **If it is not under 2s after roughly six more full runs, the prediction has
  FAILED and `lib_dns_async` is where to look.** A prediction without a horizon cannot
  falsify anything; hold T to this one.

  **Metric-trust note worth keeping:** `n` increments only on a **PASS**, while
  `learn_timeout` can raise `dur` WITHOUT incrementing `n`. So "n went 46→49" is three
  genuine passes, not three kills laundered into the average. **A `dur` that moves while
  `n` stands still is the shape to distrust.**

  **`full` at `c45ed0062` GREEN, 1226.6s, zero reds, no co-tenant** — the run this
  morning's could not be. `crtl_exp2`'s watcher EWMA is now 125.66s and T's fix gave it
  251s; under the old ceiling it would have been killed at 90s again. **`open_regressions`
  is EMPTY.**

  **A cost of the timeout bug nobody had priced:** the standing `crtl_exp2` red was the
  SOLE entry in the not-in-allowlist list keeping `would_pin` false. So it was not merely
  noise on the board — **it was blocking pin qualification outright.** `pin_verify v353
  8a16663c6ffe` is GREEN (full), `red: []`, and `pin_shadow` has flipped to
  `qualifies: true, reds 0, streak 1`, so `trackt pinstatus` can name a last-fully-green
  pin again.

  **STILL CARRIED, second check running (T's, and T's call): the `twatch.py` stub-refile
  fix (`c45ed0062`) has NOT had its daemon restart.** The clone has pulled it; the watcher
  has been in back-to-back full/pin/native runs and T will not restart mid-test, which is
  correct. **So the NEXT new red still will not auto-file.** Do not read "no ticket
  appeared" as "no finding" until a restart is confirmed — and the risk is now sharper, not
  softer, because with the board clear the next red is likelier to be a real one.

  T on the duplicate-port find: *"the one I would have missed — I audited for hardcoded
  ports and would have logged `lib_http_async`'s 28755 as one more instance of the pattern,
  not as a collision with `lib_tls` INSIDE one recipe block."* And on where it belongs:
  **a comment at the constant is checkable, where a ticket is not.**

- **check 2026-08-19 (+13h): quiet. Both workers busy, T green, pin current, nobody
  blocked.** frank2 on p88 (increment 2 designed, `829335fc7` — fill the defaults array at
  def time rather than storing global addresses); frank3 on the dns_async p45. Pin check
  ran and correctly said no: nothing under `compiler/**` since v354. T UP, native GREEN
  through `ebb7784692fb`, full GREEN through `c45ed0062491`, `open_regressions` still
  empty. Every staffed lane has a ranked head and no lane is starved.

  Only action: flagged to plexus-T that its stated "idle window" for the `twatch.py`
  stub-refile restart (`c45ed0062`) appears to be NOW — it is idle, the board is clear and
  the last tier finished. Framed as flagging the window, not requesting the restart; it is
  T's tool and T's call. **The caveat stands until it lands: "no ticket appeared" is not
  "no finding", and that is costlier now than this morning because a clear board makes the
  next red likelier to be real.**

- **CAVEAT DROPPED: the twatch stub-refile restart LANDED at 09:27:43Z**, before my message
  reached plexus-T. Verified by T rather than assumed — process start timestamp AFTER the
  file's mtime (so the running code is the fix), 4 refs present, clone clean and detached,
  no orphaned testmgr. It took SIGTERM cooperatively in 2s and dropped the in-flight full
  run, which is what a backfill survives, so none of the wedged-clone risk. **A NEW-RED on
  a job with a resolved ticket now files as `<slug>-2` and announces itself.**
  "No ticket appeared ≠ no finding" comes off the standing caveats.

- **AND THE CORRECTION IS WORTH MORE THAN THE RESTART — I conflated THREE different
  subjects and called it one signal.** At 09:27:37Z, six seconds before T restarted, its
  daemon had a testmgr child **6 minutes into a full tier**. The window I flagged as idle
  was not one.

  My evidence was `ListAgents` showing `plexus-T ... idle`, plus published tstate (native
  GREEN through `ebb7784692fb`, full GREEN through `c45ed0062491`). **Every part of that
  was true. None of it was about daemon liveness.** Three distinct subjects:

  | what I read | what it actually answers |
  | --- | --- |
  | `ListAgents` `idle` | the **Claude session's** conversational state on another box |
  | `twatch --status` | **is coverage current for this repo** — history, not liveness |
  | (never checked) | **is a child mid-run right now** |

  `--status` *cannot* answer liveness by design: a quiet watcher on a quiet repo is
  deliberately indistinguishable from a dead one, because for coverage purposes it does not
  matter. Reading it harder will never yield the answer. Same family as
  `pgrep`-matching-its-own-command-line and the `tkString`-of-a-single-char case — **a
  checkable, correct statement standing in for the deciding one.**

  **What decides it (T's, run before flagging a window again):**

      ps --ppid $(systemctl --user show -p MainPID --value trackt-watcher.service) \
         --no-headers | wc -l

  Zero, **re-checked ~5s later** to avoid landing in the gap between two child processes.
  Plus `git -C <clone> symbolic-ref -q HEAD` for the wedge check. **State, not
  evidence-of-state.**

  No harm this time — flagging rather than asking was the right move with an uncertain
  signal, and T said as much. But a false idle reading is how a restart lands mid-test, and
  T priced that at **11 hours**. Do not spend that on a signal that was never about the
  subject.

- **frank3: dns_async landed (`6c89e9cc0`), and UDP fails DIFFERENTLY — the finding is
  bigger than the fix.** Verified here: 213 lines in `test/lib_dns_async.pas`,
  `BindEphemeralUdp` at one site feeding three call sites, lib-test green on v354.

  **The warning I passed on ("a UDP/PAL shape may not wedge the same way TCP did") was the
  whole ticket**, and frank3 says verifying against "does it wedge?" would have passed a
  test that proved nothing. Two concurrent copies of the PRE-fix binary gave **both**
  failure modes at once:

  - copy 2: exit 124, killed at 25s, zero output — the predicted hang;
  - copy 1: **exit 0, 17 `=ok`, 4 FAIL** — `chase-rcode`, `chase-count`, `chase-ip`,
    `cache-1query`.

  **Copy 1 is the one that matters.** A UDP socket does not refuse a second binder the way
  a TCP listener does — **it splits the traffic**, so copy 1 answered its neighbour's
  queries. The collision therefore presents as *a regression in CNAME chasing and in the
  DNS cache, in the file whose entire subject is CNAME chasing and the DNS cache.* One turn
  worse than lib_tls: there a port fight looked like a TLS timeout; **here it looks like a
  DNS logic bug and hands you the wrong suspect.** Solo it passes — it passed for T too.

  **The trap that would have "fixed" the file into uselessness:** the truncation pair could
  not take port 0. The resolver falls back UDP→TCP **on the same port number**, and the two
  protocols have separate port spaces — binding both to 0 independently gives two different
  numbers, the fallback dials nothing, and **the test goes green with its coverage silently
  removed.** UDP binds 0 and publishes; TCP takes that number in its own space.

  Shape notes worth keeping: **one `BindEphemeralUdp` rather than six patches** — six bind
  sites was six chances to fix five of them. `CacheServerCo` already had a deadline and was
  the one correct site *for a reason*: there "no second query arrived" IS the assertion, so
  it had to have a timeout to mean anything. Verified at 2, 6, 10 concurrent plus 3×4;
  every copy 22/22.

  **frank3 corrected its own earlier ticket and I had relayed my version of it to T.**
  `lib_net6` is not merely "warty": every `NetTcpListen`/`NetUdpBind` is checked and
  `Halt(1)`s with a named FAIL, so a collision there is **loud, not a timeout, and cannot
  be contributing to T's EWMA.** Its six hardcoded ports stay deliberately — the test
  asserts the *sender's* port (`if src.Port <> 28853`), so port 0 needs the read-back
  threaded through the assertions. Recorded in the ticket so the next auditor does not read
  "hardcoded" as "hangs".

  **T's falsification horizon is now sharper, and this was relayed:** dns_async was the
  LAST hang-capable file in lib-test. Remaining candidates are all loud-on-failure, so if
  the EWMA misses under-2s after ~6 more full runs, the cause is **outside the port class**
  and **a timeout from here is new information rather than more of this.**

- **T: EWMA tracking the curve, and the UDP finding is now a standing triage rule.**
  11.2 → **7.57s** over n=49→50, against 7.2 predicted from the previous sample. Geometric
  decay toward ~1.2 holding, one sample per full run; **under 2s within about five more.**

  T took the sharpened framing and named what it bought: *"that converts the horizon from a
  prediction into a discriminator, which is worth more."* Recorded in `track-t.md`
  (`9bfb7fcfa`) as a triage rule rather than left in a message, on the grounds that it is a
  fact about **how the harness misreads reds**, not a fact about DNS — with frank3's
  measured pair verbatim, because *a red arriving with a specific, plausible, WRONG
  diagnosis attached is the shape triage is least able to resist. A hang at least announces
  itself as a duration signal; this announces nothing.*

  Both corollaries kept, and T flagged both as corrections to its own earlier readings:
  **audit for unchecked BINDS, not for literals** (it had `lib_net6`'s hardcoded ports on
  its list; every bind there is checked and `Halt(1)`s, so it is loud and cannot touch the
  EWMA — *"'hardcoded' was the wrong predicate; I was auditing the visible thing rather
  than the deciding one"*), and **port 0 is not always available as the fix** (the UDP→TCP
  fallback shares the port NUMBER across two port spaces), which matters precisely because
  port 0 is now house style and will be applied by someone who has not hit it.

  Two more T bugs closed in the same commit, both affecting records I read: `fuzz.sh`
  compared the **reaper's** stderr, so an identical crash on all four targets — the
  strongest possible evidence of NO backend divergence — was reported as three
  DIVERGENCEs on every crashing mutant; and `pin_verify` recorded **positional** job names,
  so a red in it could not be attributed without knowing which sha to resolve against.

- **A WITHDRAWAL WORTH MORE THAN THE FIXES — the "stale version label" defect was not
  real, and T nearly shipped a fix for it.** `ver` and `sha` come from **one line** of
  `pin.log` and are paired at the source. **Verified here** — that is exactly the shape of
  the two most recent entries, version and sha written together in a single record, so they
  cannot drift apart. The apparent evidence (VERSION reading 346 in a tree recorded as
  v347) holds for **every pin ever taken**, eleven of eleven, lag exactly 1 — because
  `make pin` records the pin against the sha it was built FROM, and the VERSION bump lands
  in the pin commit AFTER it. **The proposed fix would have relabelled every verification
  with its predecessor's version.**

  Honest split on verification: I confirmed the structural claim (one line, paired at
  source — the decisive one, since it makes drift impossible). The eleven-of-eleven lag
  audit is T's own artifact on T's box and is taken on its word; there is no `VERSION` file
  in this repo to check it against.

  **The class: a perfectly consistent anomaly is evidence of a CONVENTION, not a bug.**
  A defect that holds for 11 of 11 cases with a constant offset is describing how the
  system is built. Mirror image of the stale-comment class this week — there the prose was
  wrong and the code right; here the *evidence* looked wrong and the design was right.

- **check 2026-08-19 (+14h): pinned v355 in an idle window; ONE OWNERSHIP FORK IS WITH THE
  USER.** T UP, full GREEN through `9bfb7fcfac03`, no reds. Pin `739dfeb2d0e8` at
  `264489d47360` — taken because `580e6d1ba` (p88 increment 2a) moved `compiler/**` and
  both workers were idle. Second time the idle-fleet rule has paid; it costs nobody
  anything at that moment.

  **The fork: Track B has drained to p30, and the top corpus lever is blocked behind Track
  N work that frank2's own feature will contend with.** `feature-b-mimic-collections-abc-…`
  (B, p68) needs the two N bugs at the head of N (`…keys-items-values…`,
  `…for-loop-getitem-protocol-fallback`, both p68). frank2 holds A+N with human-confirmed
  sole-A and is mid-p88.

  **Measured, not assumed** — I asked frank2 for the file facts before framing anything:
  landed p88 is emission-side ONLY (`compiler.pas`, `defs.inc`, `rtti_emit.inc`), but 2b
  needs `pyparser.inc` (the def-init queue) and 2c needs `pylib.pas` + `pyeval.pas`
  (`TPyBoundRec` grows in one place, read in two). Both N tickets are `pyparser.inc`
  dispatch work. **So the overlap is real and the file-grounds case dies.**

  **frank2 supplied a third option I had not framed, and it is my recommendation:** stop
  p88 at **2a** — already clean, green, self-contained, with 2b/2c/2d banked in the ticket
  so resuming costs no re-derivation — let frank3 take both N bugs with `pyparser.inc`
  uncontended, and resume p88 after. It **serialises p88 instead of the corpus lever**, and
  p88 unblocks nothing currently moving while B is down to p30. I had framed the question
  as two options and the frame was wrong.

  **Worth recording as conduct:** frank2 measured that the two edit regions sit far apart
  in a ~34k-line file and would very likely merge clean — then explicitly refused to let
  that read as a reason to overrule the lane rule, offering it only as a reason the user
  might judge the risk small. *"Mergeable is not free to mix"* is CLAUDE.md's own line, and
  a worker volunteering the fact that cuts against the rule it is subject to, correctly
  fenced, is the behaviour that makes these reports trustworthy. Passed to the user in
  those terms rather than flattened either way.

  frank2 told to keep going on p88 but **not** to start 2b's `pyparser.inc` edits until the
  user rules — pressing on loses nothing if they agree (2a is already the stopping point)
  and avoids a burned increment if they do not.

- **DISPATCH MODEL CHANGED (user, 2026-08-19): standing goals, workers self-dispatch.**
  Both workers idle for the third check running is what prompted it. Goals set:

  - **frank2 (A+N, sole-A):** land the two N p68 bugs FIRST — `…keys-items-values…` then
    `…for-loop-getitem-protocol-fallback` — because they unblock the corpus lever; p88
    stays parked at **2a** (its own clean self-contained point, 2b/2c/2d banked); then
    resume p88; then self-dispatch `next --track A|N`.
  - **frank3 (B):** drive B's queue to dry, self-dispatching from `next --track B`. Head is
    the p30 strtofloat perf item, then the p20 ULP pair. **Standing override: when the two
    N bugs land, drop everything and take
    `feature-b-mimic-collections-abc-mapping-and-mutablemapping` (p68)** — worth more than
    the rest of B's queue combined.

  **The ownership fork I raised is WITHDRAWN — I manufactured it.** frank2 already holds N;
  those tickets are in its own lane; the real question was ordering, which is mine. It only
  looked like an ownership question because I framed it as reassigning them to frank3.
  Rule recorded above.

- **PIN v356 (11:24Z) — the corpus's top lever is unblocked.** `2bb09afb0cff` (was
  `739dfeb2d0e8`) at `5b93f1155a7b`. frank3 raised it as the one blocker it could not
  route, and it was right: `feature-b-mimic-collections-abc-…` showed **READY** because
  both blockers were in `done/`, while neither was in the pin — `810f219c3` 13:01 and
  `6905d6fd0` 13:07 against v355 at 10:34. Verified independently here with
  `merge-base --is-ancestor` (NO for both), and frank3 had already confirmed **by running
  the pinned binary** rather than inferring from commit order.

  **`ready` does not know about the pin.** A Track B ticket can rank READY on `done/`
  blockers that Track B's ground cannot yet see. That is the "fixed at HEAD" vs "unblocked
  for B" split wearing a new hat — the queue itself will tell you to start work that cannot
  work. Worth watching for whenever a B ticket depends on compiler-side fixes.

- **frank3: StrToFloat landed (`cc50090c2`), gate met first time in five passes.**
  Subnormals 47-70x; cumulative from the filing rows ~184x mid-range, 259x small, 317x
  subnormal, for +11.8 KB code and no table (Lemire's is +42 KB). ExBinNearest compares
  `m·2^k` against `d·10^expo` in binary big integers — every power of two is a shift, and
  `5^|expo|` is built once per parse rather than once per comparison. The Lemire-style
  decline is **live, not dead code**: 43,528 values answered by the fast path, 800 still by
  ExDecNearest on the gated test.

  **The finding is about testing, and it came from the oracle instruction:** inverting
  round-to-even changed **NOTHING** across 125,609 values, because random decimals
  essentially never land exactly halfway between two doubles — **the tie branch had zero
  coverage while looking thoroughly covered.** Twelve exact midpoints from CPython's
  `Fraction` are now gated. The perturbation table is the right way to prove a suite has
  teeth: 5^13 off-by-one → 23,272 mismatches; midpoint 2m+1→2m → 21,183; flipped tie rule
  → 60; **dropped 2-power cancellation → 0**, which is the correct answer for a
  semantically neutral change and is what makes the other three trustworthy.

  **Two numbers withdrawn: CPython does NOT parse `1e-320` in 0.72 µs** — that target had
  been in the ticket for two passes and does not reproduce; the real gap is **3-6x, not
  15x**, and pxx is now **2.1x faster than CPython** for normals past Clinger's window.
  frank3's own note: that is the **fourth** number in this ticket's history to need
  re-measuring, "which is starting to look like a property of the ticket rather than of the
  measurers." Same class as the three stale justifications found earlier today.

  Second-order win worth noting: the gated test got **stronger because the fix made
  coverage affordable** — its boundary blocks had been capped at 1500 values because each
  cost ~500 µs; now 112,207 values in 1.8 s where it was 73,195 in 2.8 s. Next lever filed
  (`feature-b-strtofloat-big-integers-in-64-bit-limbs`, p25), residue established by
  **counting** (6 comparisons, not "many") and by ruling out copies with a 3.5x smaller
  buffer that moved the row only 13%.

  Also closed `bug-n-the-sequence-protocol-does-not-yield-iteration` as a duplicate to
  **`rejected/` rather than `done/`** — the fix did not land under it, and the point of the
  move is that it cannot dispatch a third agent onto finished work. The reasoning is better
  than the convention.

- **check 2026-08-19 (+15h): pin current, T green, frank3 on the Mapping shim, frank2
  IDLE despite a standing goal — nudged.** Pin v356 (`2bb09afb0cff`) still current; nothing
  under `compiler/**` since. T UP, native GREEN through `9551d37bad93`, full GREEN through
  `9bfb7fcfac03`, no reds.

  frank2 parked p88 into `unfinished/` at a genuinely clean point — 2b part 1 green, a
  RESUME AT note, and the hazard written down (*"nothing may consume the defaults array
  until 2b part 2 lands"*, since string and non-constant slots hold `PYSIG_DFLT_UNSET`).
  The park is good work; the idling after it is the problem, since its standing goal was
  resume-then-self-dispatch. Asked what stopped it, and cleared the two likely reasons:
  **2b part 2 needs `pyparser.inc` and is uncontended** (frank3 is in `lib/rtl`, and the
  overlap worry died when frank2 took the N tickets itself), and **2c's pin is available on
  request, immediately.**

  **Flagged but not demanded: p88 is `track: A` and sits in `unfinished/`** — the case
  CLAUDE.md calls critical, because a half-applied compiler change can threaten the
  stable-binary gate. This one is safe (green, self-hosting, pinned, loud sentinel by
  design), so it is a reason not to leave it parked *long* rather than a reason to unpark
  now. `tools/progress.sh check` reports "board OK with warnings", so it is not tripping
  the mechanical guard.

  **Board hygiene found and NOT yet actioned: 24 resolved tickets await their landed sha**
  (`PENDING-COMMIT`, fixed by `tools/sync.sh`). Deliberately deferred while frank3 is
  mid-work — `sync.sh` commits and pushes, and racing a busy worker for board files is how
  a rebase conflict on generated BOARD files happens. Run it in a quiet window. This is the
  coordinator's housekeeping, not a worker's.

- **Mapping shim landed and the ladder DID NOT MOVE — the honest headline, and the blocker
  is one line up the stack.** frank3 reported "past a wall: ZERO files" as its own headline
  immediately after landing the thing, which is the discipline the mandate asks for.

  **Root cause verified here, not relayed:** `PyImportRootIsConsumedOnly`
  (`compiler/pyparser.inc:33007`) tests only the ROOT of a dotted from-import and has
  `collections` on its consume-and-ignore list, so `from collections.abc import Mapping` is
  swallowed whole and binds nothing. The function's own comment states the assumption that
  broke: `collections` is listed because *"the names it exports that we support are
  ordinary pylib symbols … and an unsupported name walls visibly at its use site"* — true
  before a real submodule shim existed. `import collections.abc as cabc` reaches the shim;
  `from xml.etree.ElementTree import Element` works because `xml` is not on the list.

  **The shim is correct and load-bearing, and frank3 proved it rather than asserting it:**
  mechanically rewriting the 7 files' import spelling puts `_trie/_base.py` clean through
  and four more onto a later unrelated `undefined variable (__name__)`. It also perturbed
  the shim five ways before believing a zero-diff 47-assertion differential. **`MutableSet`
  omitted after checking the actual corpus imports** — only Mapping, MutableMapping,
  OrderedDict, deque, namedtuple are ever asked for.

  **Routing: the blocker is Track N and goes to frank2** (`bug-n-from-collections-abc-…`,
  p62) — its lane, it is active in it, no ownership change needed. Queued to it directly so
  it does not have to come back for the next item.

- **UNPUSHED WORK, caught by verification: `348f56dc7` does not exist in this repo.**
  frank3 reported the shim as LANDED and five tickets as FILED; `git cat-file -t` says
  "Not a valid object name" and `origin/master` has none of it. So Track T cannot test it,
  `ready`/`next` cannot see the five N bugs — **including the p62 corpus blocker** — and
  nothing can be ranked. Asked for an immediate push.

  **Worth keeping as a check: "landed" from a worker means landed in ITS tree.** Verify a
  reported sha exists on origin before ranking, routing or relaying it. Cheap
  (`git cat-file -t <sha>`), and a filed-but-unpushed ticket is measured-but-not-filed —
  the exact failure this repo keeps recording, one step upstream of where it usually
  appears.

- **A THIRD sighting of one root cause, flagged by frank3:**
  `bug-n-a-subscript-inside-a-base-class-skips-the-subclass-override` is the sibling arm of
  the already-resolved `bug-n-a-builtin-subclass-subscript-operator-skips-the-override`
  (confirmed in `done/`), which fixed only the builtin-base half. Per
  `root-cause-over-microfix.md` that is a design flaw, not three bugs. Asked frank3 to put
  the three-arm framing **in the ticket body**, not only in its report — otherwise whoever
  takes it fixes the third arm and leaves the fourth.

- **Track B is thinning** — after the shim resolves, its queue is
  `feature-b-strtofloat-big-integers-in-64-bit-limbs` (p25) and two p20 ULP items. frank3
  is on the p25. Noted for the user as a heads-up; not raised as a fork, since B still has
  its own work and the leverage sitting in N is being routed to N's owner.

- **frank3 pushed — verified on origin.** `a3eaec78b`. All five N tickets present with the
  prios reported (`…collections-abc-import-is-swallowed…` p62,
  `…mixin-cannot-iterate-self…` / `…subscript-inside-a-base-class…` /
  `…hasattr-through-an-untyped-parameter…` p55, `…isinstance-qualified…` p45); the Mapping
  shim is in `done/`; both workers now hold locks in `working/`.

  **Its own account of the miss is the useful part:** it committed, then went straight into
  the next ticket's rewrite with the push outstanding — *"I treated push as something to do
  after the next thing."* That is the specific shape, and it is more useful than the rule it
  broke. The three-arm framing was already in the ticket body before I asked, and it
  verified that after pushing rather than assuming.

  **One refinement it added to the import blocker, worth carrying into the fix:**
  `PyImportRootIsConsumedOnly`'s comment justifies listing `collections` on the grounds that
  *"an unsupported name walls visibly at its use site"* — and that premise is what broke.
  The failure is now **silent**: the from-import binds nothing and the error surfaces later
  as `unknown base class Mapping`, pointing at the class rather than the import. So the
  ticket is as much about the comment's premise as the list's contents. Relayed to frank2.

  Board hygiene still open and still deferred: **24 resolved tickets await their landed
  sha** (`PENDING-COMMIT`, `tools/sync.sh`). Both workers are busy, and racing them for the
  generated board files is how the rebase conflicts happen. Run it in a genuinely quiet
  window.

- **TWO MEASUREMENT HAZARDS FROM frank3, and one of them was live in the coordinator's own
  pin procedure.**

  **1. A measurement in flight is also a lock on the CPU — and a benchmark is the
  measurement most likely to be SILENTLY wrong rather than visibly broken.** frank3 ran a
  before/after benchmark with three perturbation compiles still on the box (load 2.3), got
  ~1.6-1.9x against a predicted ~4x, and caught itself *starting to explain the shortfall*.
  Its own framing: **a contaminated correctness run usually errors; a contaminated
  benchmark just returns a plausible number** — so it would have shipped a wrong ratio with
  a story attached. Discarded, not caveated, per the rule from the previous check.

  This is the second half of "a measurement in flight is a lock on the files it reads",
  and it widens the coordinator's obligation: **a pin is a CPU event as much as a tree
  event.** Do not pin while a benchmark is running, even though a pin cannot corrupt its
  files.

  **2. A stale binary of unknown provenance in the scratchpad.** frank3 nearly reported
  numbers from a `bench_new` left by an earlier session: the compile that was supposed to
  produce it had **failed**, the stale binary ran anyway and printed sensible-looking rows.
  Caught only because the row labels did not match the source just written. CLAUDE.md's
  "verify against a known sha" is usually read as being about the *compiler* binary — **it
  applies to the harness too.**

  **And the mechanism behind it was live HERE.** `make x 2>&1 | tail && make y` runs `y`
  even when `x` failed, because a pipeline's status is the last command's and `tail` always
  succeeds. **That is exactly the form the coordinator used for all four of today's pins**
  — so a failed `stabilize-fast` would have been followed by `make pin` regardless, pinning
  a binary whose fixedpoint never passed. Verified with `false | tail -2 && echo RAN`.
  Never bit, because every run printed `STABLE vNNN OK`; the pin command in the standing
  rules above now carries `set -o pipefail` and says why.

  **Worth naming: a worker reporting the SHAPE of its own mistake rather than just its
  instance is what let this be caught in the coordinator's procedure.** frank3 had no
  reason to think the pin loop had the same bug, and did not go looking — describing the
  mechanism was enough.

- **PIN v357 (12:03Z)** — `2165452af333` (was `2bb09afb0cff`) at `ad71a3749897`, carrying
  p88's `9c5148087` and `e78cc5882`. **First pin run with `set -o pipefail`;** the four
  earlier pins today used the unsound form and the commit message records that. New
  `$(PXX_STABLE)` md5 `cf7bce71808530b2eca30ca70f580877` was sent to frank3, which now
  captures the toolchain identity before each measurement.

  Held ~10 min for frank3's A/B, released the moment its post-run hash re-check matched.
  frank3 then asked to be pinned *before* its `lib-test` rather than after, on the grounds
  that **Track B ships on the pin, so gating against the pin the compiler commits produce
  is the more meaningful green** — correct, and strictly better than the sequencing I would
  have chosen.

  **The strtofloat limb result: 1.6-1.8x on heavy rows against a predicted ~4x, recorded as
  gate UNMET.** Fixed model from an instrumented limb counter: **~9.2 ns per limb op plus
  ~2.8 µs fixed per-parse setup**, which independently reproduces the parent ticket's
  separately-measured 2.5-3.5 µs — corroborated, not fitted to itself. **The redirect that
  matters for future ranking: ~2.8 µs is fixed setup no limb-width change can touch, so
  anyone chasing another 2x on subnormals should attack the SETUP, not the limbs.** Asked
  for that to go in the parent ticket body, since it is invisible to `ready`/`next`
  otherwise and would cost the next optimiser a whole ticket.

- **INCIDENT: pin v357 was BAD and is REVERTED (`5a0e894b3`). Track B was blocked ~20 min.**
  I pinned it; the fault is mine to own even though the defect is not.

  v357 carried p88's `9c5148087` + `e78cc5882` and broke **compilation** of
  `examples/tk/callbacks.npy:84` and `htmlview.npy:51` with *"callable value of a def with
  no signature record"*. **Verified here both directions with the pinned binary before
  acting** — v357 errors (`near: root update >>> unit builtinheap`), v356 gives
  `ok, code=2530315B`, and `hello.npy` compiles on both, so it is not the whole Tk path.

  Routed to frank2 as `urgent/bug-n-pin-v357-…` (N, **p90**), outranking its own p88 work,
  carrying everything frank3 had already established so it is not redone: not frank3's
  change (reproduced clean with its work stashed), **not minimisable** — `g = f; g()` and
  `h = c.m; h()` both compile fine on v357 — so it needs something the pcl/Tk path does.

  **frank3 stopped short of a minimal repro deliberately**, on the grounds that a blocked
  lane is worth more than a tidy test case, and reported immediately. Correct call: the
  lane was clear in twenty minutes and the minimisation would have bought the fixer little
  that the bounds already give.

  **It also refused to resolve its finished strtofloat work against a red gate** — held it
  instead. Right, and worth naming: a green ticket landed against a broken ground is how a
  false record gets written.

  **What this incident actually proves is the gating order** (now a standing rule above):
  gating post-pin is what surfaced it. Had frank3 gated before the pin, it would have had a
  true green against v356 and the tree would have carried a blessed, broken pin.

- **PIN v357 (second attempt) IS IN — `5d23a9554467` at `21c051b97d80`, md5
  `ebcf15ccb1046b29353b3b85091a8cdc`.** Verified against the known-failing repro BEFORE the
  commit landed: `callbacks.npy` ok 2520362B, `htmlview.npy` ok 2608593B, `hello.npy` ok
  2356393B. That check is the procedure change the first v357 earned.

  **Root cause was one thing with two arms, and it was never Tk.** `EmitPySignatures`
  skipped any def with `ProcUnitIdx >= 0` — a guard to keep Pascal RTL routines out (+170 KB
  of `.data` on the self-build without it) that **also excluded defs in imported `.npy`
  modules**. Every Tk app hands a callback across a module boundary; `g = f; g()` never
  crosses one. Predicate is now `PyProcIsNilPyDef` — *"did the NilPy frontend parse this"*
  rather than *"is it local"*, which is what the guard meant all along. **Second arm:** the
  sentinel resolver raised a hard `Error` on a missing record; it now degrades to a zeroed
  scratch record (`TotN = 0`), so a future gap of this shape is a silent no-op rather than a
  blocked lane. My hypothesis (2b part 2 introduced a consumer) was **wrong** — `PYSIGD`
  already bit-bucketed its misses; it was 2c's `PYSIG` sentinel with the hard error.

  Also carried: 2b part 2, **2c and 2d** — the callable value now carries its signature and
  the bridge fills the callee's defaults, with `test_nilpy_callable_value_defaults.npy`
  wired into `test-nilpy` against a CPython-generated expectation.

  **CORRECTED: I did NOT swap the pin under frank3's in-flight `lib-test`.** Both of us
  believed I had; the trees are separate clones, and frank3 later confirmed by a mid-suite
  hash sample at 130 targets that its `$(PXX_STABLE)` never changed. **A clean run was
  binned on our shared wrong premise, and this roster recorded the contamination as fact
  before anyone checked.** The protocol residue that survives is smaller: `pgrep` before a
  lock is still right, but for CPU, not for a neighbour's files.

  **Two pre-existing holes, measured on `PXX_STABLE` too, so the pin neither opens nor
  closes them:** a callable reached through a *subscript or parameter* and called with fewer
  args than declared still segfaults (`fs = [g]; fs[0](1)`) — the last unfixed row of p70's
  table, frank2 staying on it; and `bug-n-sorted-by-a-key-returning-a-string-bearing-tuple-segfaults`
  (N, p55), filed with its boundary.

  **frank3's self-correction, worth as much as the fix:** *"I treated a passing sibling as
  noise bounding the blast radius, when a passing sibling in a family of near-identical
  cases is a DISCRIMINATOR."* `hello.npy` passing was not "not the whole Tk path" — it was
  naming the module crossing as the boundary, and it was already in hand. Same shape as its
  dead-code find this morning: **the result read as uninformative was the informative one.**

- **v357 GREEN on the full `lib-test`, strtofloat limb work landed (`1f97cbbdf`).** frank3
  captured the pin hash before the run and re-checked it unchanged after, so the result
  holds on its own evidence rather than on the coordinator's hold. `tk-nilpy: ok`,
  `StrToFloat matches CPython on 112207 values`, zero failures.

  **Headline recorded as UNMET**: predicted ~4x, delivered 1.6-1.8x. frank3 led the commit
  message with the shortfall and the double-counting error rather than the gain, *"because
  that is the part that transfers"* — second time today it chose the version of a result
  that transfers over the version that flatters. What the change earns its place on
  instead: 2.2x less limb work, `BigFMulU64` collapsed to a one-liner, `BigFAdd` deleted as
  dead, and the **~2.8 µs fixed-setup floor written into the parent ticket where the next
  optimiser will look**.

- **TRACK B IS DRY — a staffing question is with the user.** `next --track B` is
  `bug-nilpy-complex-pow-is-a-few-ulp-off-cpython` at effective prio **20**; everything
  above it is done. frank3's own read, which I agree with: **B has no high-value work left
  that is not downstream of N**, and a few-ulp `complex_pow` difference is not worth a
  session while the corpus ladder is stalled on an import rule.

  Routed frank3 to the one thing that is unambiguously its own: **re-run the corpus ladder
  clean on v357.** Nobody currently holds a current ladder reading — the contaminated run
  was binned unread and never replaced — so this re-baselines what the generator series
  plus three pins actually bought, which is the mandate's headline number.

  **The ownership fork DISSOLVED before it reached the user.** frank3 offered to take
  `bug-n-from-collections-abc-import-…` (N, p62) with the diagnosis loaded; minutes later
  frank2 resolved p88 (`b515f2842`) and **took the import blocker itself**, as queued. So
  there was nothing to decide — again. That is twice today a lane-ownership question
  evaporated within the hour simply by waiting for the lane's owner to finish. **Worth
  making a habit of: before escalating an ownership fork, check whether the owner is about
  to be free.**

  **What remains for the user is narrower and real: frank3 has nothing above p20 after the
  ladder re-run**, and every high-value item left is in a lane it does not own.

- **p88 RESOLVED (`b515f2842`), and frank2's correction is the model.** It had told me the
  segfault it was chasing "does reach my dispatcher". **It does not.** It had been mapping
  the IR's bare `call a=1508` back to a callee **by assumption**; it built
  `PXXDBG=n.procs` (`b54939cf3`) to print the proc table instead, and the real site is
  `pyvar_callv1` carrying **tag 12** (the boundfn carrier), not the tag-8 pair the signature
  record hangs off — a path its code never touched. An hour lost to reasoning about a
  number instead of printing it, the tool now in the tree so nobody repeats it, and the
  correction published against its own earlier claim.

  **p88's scope is therefore MEASURED, not claimed:** correct for the tag-8 pair
  (`f = some_def`, `obj.method`, `map`/`filter`/`sorted(key=)`, byte-identical to CPython in
  the wired test); **not** covering a def reached through a subscript or parameter
  (`fs = [g]; fs[0](1)`), which rides tag 12. Pre-existing, identical on `PXX_STABLE`, filed
  as `bug-n-a-module-level-def-taken-as-a-value-loses-its-defaults-on-the-boundfn-carrier`
  (N, p65).

- **DESIGN FINDING BANKED, NOT MICROFIXED — four dispatchers, two defaults mechanisms.**
  frank2 counted: **four** dynamic-call dispatchers (`pybound_callv*`, `pycallback_call*`,
  `PyCallKey1`, `pyvar_callv*`) and **two** independent defaults mechanisms for one
  concept — the new signature record (tag 8) and `pyboundfn_setdefaults` (tag 12), the
  latter already firing for the NESTED def form and not the module-level one, which is the
  sibling-arm-left-behind shape that site's own comment records about the lambda lifter.

  Its call, and it is the right one: **put `Sig` on the boundfn carrier and DELETE
  `pyboundfn_setdefaults` — one mechanism, fewer cases — rather than teach a fifth path the
  same trick.** `root-cause-over-microfix.md` says three is a design flaw; four and two is
  past arguing. **Routed SECOND**, after the `collections.abc` import blocker, because the
  import bug is the only one with a queue behind it: frank3's Mapping shim landed inert and
  7 corpus files start moving the moment the import reaches it. Ordering, not ownership, so
  mine to set.

- **check 2026-08-19 (+17h): T green, nobody blocked, PIN DUE BUT HELD.** `b54939cf3`
  (`PXXDBG=n.procs`) is past v357, so a pin is due — **held** because the pre-lock `pgrep`
  found two `nilpy_ladder.py` runs on the box. That check is now earning its keep: under
  the old habit I would have announced and started, exactly as I did an hour ago.

  T UP, native GREEN through `44da14d4ff76`, full GREEN through `9bfb7fcfac03`, no reds.
  `working/` is empty while both workers are mid-measurement — the locks are genuinely
  free, not misreported.

  **Coordination note: BOTH workers are running the ladder simultaneously, from separate
  clones.** frank2 bare, frank3 with `--files`. Two hazards, neither severe: they contend
  for CPU (making both slower), and **two independent clones may sit at different shas, so
  the two runs can produce two legitimately different numbers that a later reader compares
  as one measurement.** Told frank2 to name its pin sha + md5 if it publishes, and that
  frank3's `--files` run supersedes a bare one. Did not ask it to kill anything.

  **Generalisable: a shared measurement should be run ONCE and shared, not re-derived per
  clone.** Nothing surfaces "someone else is already measuring this" — same blind spot as
  pin staleness, and the coordinator is the only one positioned to see it.

  Queue state: A's head is now `bug-a-make-revert-the-documented-pin-brake-does-not-fire`
  (p60, filed by frank3 off today's incident — the documented brake does not fire, which
  cost a real incident's worth of confusion). N's head is `bug-n-a-call-through-a-callable-
  value-drops-the-callees-defaults` (p70), READY again now that p88 resolved and cleared its
  blocker — **but frank2's tag-12 finding means it is NOT fully subsumed after all**, and its
  residue is filed separately as `bug-n-a-module-level-def-taken-as-a-value-loses-its-
  defaults-on-the-boundfn-carrier` (p65). Whether p70 is now a duplicate of that is frank2's
  call to make against a measurement, not mine to assume — it said it would verify the p70
  table before resolving anything.

## A pin's CONTENTS are an ancestry question, never a timing one (2026-08-19)

The coordinator told a worker that pin v358 was "the run that measures the shim and
frank2's fix together", and it was not: frank2's `collections.abc` fix (`703701e00`)
landed **after** the commit the pin was built from (`b54939cf3`). The worker started a
~40-minute corpus ladder on that promise. The ladder reads
`stable_linux_amd64/default/pinned`, so every file in it would have been compiled by a
compiler predating the fix — and the `Mapping` row would have sat still, reading as
*"frank2's fix did nothing"* about a fix that is measured-good.

**Where the reasoning went wrong is worth more than the outcome.** The claim was made from
*timing* — the fix and the pin happened in the same stretch of the afternoon, so the pin
"obviously" had it. Ordering by recollection is not ordering. One command answers it:

    git merge-base --is-ancestor <fix-sha> <pin-base-sha> && echo IN || echo NOT-IN

**Rules:**

- **The coordinator publishes what a pin CONTAINS, and that is a claim requiring
  measurement.** Publish the pin base sha alongside the md5, and when telling a worker a
  specific fix is in, show the ancestry check. Workers plan long runs on this; it is the one
  coordinator statement with a multiplier on it.
- **A resolve commit is not an implementation commit.** `b515f2842` "resolve(N): p88"
  touches only `devdocs/progress/**`. Checking ancestry against *it* would have answered a
  question about paperwork. Check the commits that touched `compiler/**`.
- **"In flight" vs `done/` is one `ls` away, and the difference inverts the plan.** A worker
  reported a wall as "downstream of work already in flight"; the ticket was in `done/` and
  landed, so nothing was waiting on it. The coordinator let the framing stand without
  checking the directory. Same family as *a file existing is not evidence about its state* —
  here, a ticket's **location** is the cheap fact and it was not read.

**And the thing that actually caught it:** the worker stated its intent back
("this is the run that measures the shim and frank2's fix together") instead of just
acking. That sentence is what made the wrong premise visible while it was still cheap.
Encourage restating the purpose of a long run before starting it — it is the only
cross-agent check that costs nothing.

## Killing a healthy run: progress is about cost, value is about the answer (2026-08-19)

A worker had a ~40-minute corpus ladder 833s in. Two fixes had landed that the run could
not see, so the pin was held on it, and the pin held the repo-wide lock. The coordinator
offered the choice and asked **"how far along is it?"** — and that question was the error,
even though the worker answered it correctly.

**The worker's substitution, kept in its words because it is the general rule:**

> *"How far along is it?" is the wrong question when the output is already known — the
> right one is "what does finishing tell me that I do not have?" Progress is about cost;
> value is about the answer.*

Here finishing would have produced a corpus-level confirmation of a fix already established
at file level (7 files moved, 3 compiling clean). A second measurement of a settled fact,
bought with a lock held across every lane. **Even at 95% done that trade is bad** — and
"it's nearly finished, let it run" is sunk-cost reasoning wearing the clothes of thrift.

**Three things to take from it:**

- **The coordinator asking "how far along" is worse than a worker answering it**, because
  the question sets what gets weighed. Ask what the remaining time BUYS. If the answer is
  a fact you already have, the percentage is irrelevant.
- **The reflex is trained on failing runs and is hardest to invoke on a HEALTHY one.** The
  worker had spent the day discarding runs on stale ground and still nearly kept this one
  because it was succeeding. Discarding a working run on value grounds is the case worth
  rehearsing; discarding a broken one is easy.
- **Cost check, measured:** the kill released the lock in under a minute and the pin took
  about four. The whole cycle cost less than the run's remaining time almost certainly
  would have — and the worker then got a run that could answer everything instead of one
  that could answer a third of it.

**Sibling, same day, same worker:** `--require-fix` was generalised to accept a LIST before
being bitten rather than after, on the reasoning that *a gate checking one of two required
shas is worse than no gate* — it reports a green precondition for a run that cannot answer
the question. That is the day's recurring failure (a check that can pass while the thing it
protects is broken) closed structurally instead of by care.

## Check +19h — the backlog-shrink push is staffed on three lanes

**User set a new standing goal** (supersedes the corpus/NilPy theme for its duration):
pause NilPy, work **A / C / P**, prefer IR/AST-touching tickets, and **deliberately skip
high-ranked ones** because they cost more on average. Aim is *count down*. Reason given: at
265 open the user has lost oversight and many reports look trivial. Then: **"also put track T
to work, there are still open track T tickets."**

Premise verified, not assumed — filed vs resolved: 08-17 **+19**, 08-18 **+16**, 08-19
**+17**, after 08-15's -31. N is 77 of the 265, which is most of why pausing it works.
Triage + clusters: `devdocs/progress/TRIAGE-backlog-shrink.md`.

**Staffing.** frank2 = A/P slot, cluster 1 (indexing a call result), then 3 (directives),
then 4 (calling convention). frank3 = cluster 5 (C, disjoint) then cluster 2 (Write-of-a-real).
plexus-T = its own backlog, watcher confirmed UP first.

**Watcher: UP.** plexus green through `066adaecdcdd`, full through `9bfb7fcfac03`.
plexus-T confirmed the daemon survives this batch: none of its three tickets touch
`twatch.py`, and a `testmgr.py`/`tools/*` change needs no restart because twatch spawns
testmgr fresh per run. When a restart IS needed: ~2s, cooperative SIGTERM, one discarded
backfill run that re-tests next cycle (measured twice). **Push per ticket, batch the
RESTARTS** — different operations, only one costs the dev lanes anything.

**Pin held deliberately.** One `compiler/**` commit outstanding (`e360f0c5c`); frank3's
`make lib-test` was in flight at check time. Not urgent — take it when the tree is quiet.

### TWO ASSERTED GROUPINGS, BOTH WRONG, BOTH CAUGHT BY THE WORKER

Same failure twice in one hour, and worth stating as one rule rather than two anecdotes:
**I verified the thing I happened to look at, then asserted its neighbour.**

- **Cluster 2's file footprint.** Published as *"does not touch
  `lexer.inc`/`parser.inc`/`ir*.inc`"*. I read the three tickets and confirmed they are one
  code path — true — then inferred the *location* from the topic. frank3 traced it:
  `EmitWriteFloat*` in `compiler/symtab.inc` ~6940-7479, dispatch at
  `ir_codegen.inc:4708-4710`. Both shared core ground. Verifying one property does not
  license asserting a second.
- **The Track T "/tmp cluster".** Paired from slugs. plexus-T read them: one is a testmgr
  lint it owns; the other is 60 paths across **37 sources owned by C, N and B**. Shared
  concept, almost no shared work — and doing them "in one context" would have had T editing
  three other lanes, **violating the boundary I restated in the same message**. An
  instruction that breaks its own stated rule is worse than one that omits it: it reads as
  an authorised exception.

**The fix is not care, it is asking.** Both cost one message. The general form —
**a file footprint or a work-grouping inferred from a ticket's TOPIC is a guess wearing the
costume of a fact** — is the same class as inferring pin contents from timing, or a callee
from an index number. Ask the worker who is in the code; it answers from `git diff --stat`.

### Count discipline, stated to all three lanes

The push optimises for **tickets closed, never tickets closed per minute**, and never for a
number that goes down by burying things. Told frank3 not to bound the `utoa` loop if that
hides the unnamed defect; told frank2 not to close cluster 1 on four matching rows while a
frozen-string element still prints `3` where FPC prints `mid` (a *silent wrong value* is
strictly worse than the parse error it replaced); told plexus-T to file whatever wiring the
broken devtests exposes even though it makes its own number look worse.

**Do not let the ranker fight the goal:** `next`/`ready` rank prio DESCENDING and will hand a
worker exactly what this push says to skip. Take from the clusters. This is a **temporary
inversion, not a re-rating** — when it ends, resume ranking or re-rank the survivors
deliberately, because a prio field everyone ignores is worse than none.

**Open for the user (Track U):** `decide-nilpy-imports-that-collide-with-a-pascal-rtl-unit`
(p60) — eight `lib/rtl` units share a name with a Python stdlib module, so
`from classes import Foo` fails with *"no overload of Delete matches these arguments"*,
naming a unit the program never mentioned. frank2 filed options + a recommendation rather
than guessing. Parked with N.

## Check +20h — WORKERS PAUSED for a context clear; next is the import/uses refactor

**User, 2026-08-19:** *"frank2 and frank3 should pause once done with current work. I will
clear the context. And then we start working on our import/uses refactoring."* Both were told
to finish the ticket in hand, push green, and stop — **not** to start another. frank3 was
already clean. **plexus-T is NOT paused** and continues its own backlog.

**Pin v362** — md5 `6c8b911012befe60f7a0cdf8dc20b605`, base `b8099c676`, carrying
`1df7a1926` and `354f734c1`, both ancestry-verified before publishing. Tree was quiet at the
pre-lock check.

### What the next session starts on, and why it is ready

`decided/decide-nilpy-imports-that-collide-with-a-pascal-rtl-unit` → re-filed as
**`feature-a-a-bare-nilpy-import-means-python-and-another-language-needs-its-extension`
(A, p78 — user called it urgent)**. The rule: **a bare extensionless import is Python
(`.py`/`.npy`); another language needs an explicit extension; `import ... as ...` answers a
residual collision.** Both halves carried by **whitelists** (user: *"that's a matter of
whitelisting"*), not renames.

**MEASURED on pin v361/v362 — do not re-derive, and do not trust the first version of this
table, which was wrong:**

| spelling | result |
| --- | --- |
| C `#include "./lib2.c"` | **works** |
| Pascal `uses './mymod.pas' as m;` | **works** |
| Pascal `uses './lib2.c' as c;` | **works — cross-language, already** |
| Pascal `uses 'mymod.pas';` (no `as`) | unbound **by design** (`decided/decide-cross-language-qualifier-syntax`) |
| Pascal `uses mymod in 'mymod.pas';` | not supported → `feature-p-uses-a-unit-in-an-explicit-file` (P, p30, user: lower prio) |
| **NilPy `import mymod.pas as m`** | **fails — mangled to `mymod_pas`. THE ONLY REAL GAP.** |

**I got this wrong first time** by testing `uses 'mymod.pas'` without the alias and reading
the deliberately-unbound case as "unsupported", then reporting the whole feature missing.
`feature-uses-alias-as` shipped **2026-06-30**. **Two of three languages already have the
spelling.** The job is to give NilPy the equivalent, not to invent a cross-language import.

**Open spelling question, recorded in the ticket, NOT settled:** the decided form is dotted
(`math.pas`); the shipped Pascal form is a **quoted path + `as`**, which cannot collide with
Python's package syntax and so needs no extension whitelist at all. Raised because the
precedent was unknown when the fork was answered. Build the decided form unless the user says
otherwise.

**Scope trap for whoever implements it:** the eight colliding `lib/rtl` units are **three**
populations. `re.pas` and `io.pas` say in their own headers that they ARE Python's module,
and `math`/`json`/`random` behave as Python's — those must keep resolving by bare name.
Only `classes`/`types`/`strings` should stop. **No `.npy` imports those three at all**, so
they have zero test dependency. The only tests reaching a genuinely-Pascal unit by bare name
are three importing **`sysutils`** (`test_nilpy_import_does_not_publish_names`,
`test_nilpy_pyexception_bare_vs_qualified`, `test_nilpy_rtl_exception_surface`), all already
using `as su`. **The test rewrite is downstream of the spelling, not parallel prep** — there
is nothing to rewrite into today. And `sysutils` is not one of the decision ticket's eight
names, so the collision class is broader than the survey that found it.

### The backlog-shrink push, so far

Closed today under it: cluster 5's `stdarg.h` (`a54259aab`, −2204 bytes exactly as
predicted), all three of cluster 2 (`354f734c1` — one parameterisation plus one
already-fixed), cluster 1's A ticket (`1df7a1926`, eight spellings matching FPC), and T's
split-jobs lint (`20de759f0`). Deliberate non-closes, all correct: `utoa` (blocked on a live
residual — bounding the loop would bury it), cluster 1's P half (narrowed back to `backlog/`,
dyn-array arm banked), and T's 37-source `/tmp` chore (belongs to C/N/B, not T).

**Two findings worth carrying, both from frank3:**
- **A clean rebase means git placed the hunks, not that the result compiles or behaves.** It
  rebuilt and re-ran the probe after rebasing. Different claims; only the second matters.
- **A derived discriminator that happens to be correct is indistinguishable from one correct
  by construction, until the thing it was derived from changes.** `decs >= 0` meaning "does
  this writer take arguments?" was exact only because two writers were both called with `-1`
  — and the first attempted fix would have broken all five backends identically.

### Open for the user
- Spelling question above (dotted vs quoted) — a heads-up, not a blocker.
- `bug-t-sync-fills-one-spelling-of-pending-commit` may become a `decide-*`; plexus-T is
  making the call itself and will escalate only if it is a genuine fork. **~24 resolved
  tickets still await landed shas** and must NOT be auto-filled by pattern-matching
  `git log` — that is `bug-t-resolve-cites-a-sha-the-rebase-then-rewrites` at scale.

## MANDATE CHANGE 2026-08-19 — A/P/C over everything N, and re-triage the 33 "features"

**User, verbatim in substance:** defer Track N *"since it is a neverending story"*. **Track
A + P + C priority above anything Track N, even Track N bugs.** And: many A/P tickets typed
`feature` *"may well be bugs, it's a grey zone"* — plus, after weeks of bugfixing, *"some
features may be stale or already solved."*

**This supersedes the backlog-shrink push's specifics** (skip high-prio, work the p<=40 tail).
The count-down instinct still applies where it is free, but **lane priority now beats prio
number**: an A/P/C item outranks an N item regardless of the two `prio:` fields. Do not let
`next --track N` pull anyone back in.

### The population, measured

Open A/P/C by type: **33 feature**, 11 bug, 8 compat, 5 untyped, 4 refactor, 3 idea,
2 chore, 1 each task/meta/investigation.

The 33 features by filing date — oldest first, and age is the staleness proxy:

    2026-07-16 p55 A feature-signal-siginfo-ucontext
    2026-07-19 p55 A feature-a-declaration-phase
    2026-07-20 p40 A feature-a-promoint-variant-esp-targets
    2026-07-22 p40 A feature-cdecl-bodied-sysv-prologue
    2026-07-23 p25 A feature-opt-alloc-intent-hint
    2026-07-23 p35 A feature-nilpy-arc-cross-parity
    2026-07-30 p50 C feature-c-vla-via-alloca
    2026-07-31 p20 A feature-cli-widgetset-flag
    2026-08-02 p55 A feature-nilpy-object-reclamation
    2026-08-03 p40 A feature-a-typeref-migrate-consumers
    2026-08-03 p60 A feature-opt-store-reload-elimination
    ... 22 more, 2026-08-06 onward

**Three are NilPy-motivated but filed under A** — `feature-nilpy-arc-cross-parity`,
`feature-nilpy-object-reclamation`, `feature-nilpy-cycle-collector`. They are core ARC/GC
machinery, so the FILES are A, but the motivation is N. **Rank them as N under this mandate**
unless something else needs them; the letter is about file ownership, not about what the work
is for.

### The triage, and what makes it worth doing rather than just re-reading

Three questions per ticket, in this order, because the first two can close it outright:

1. **Is it already solved?** Weeks of bugfixing may have landed it incidentally. **Compile the
   ticket's repro against the current pin.** This is the cheap, high-yield question and it is
   a MEASUREMENT, not a reading — a ticket's prose is a snapshot from its filing date.
2. **Is it stale?** Superseded by a decision, a redesign, or a different mechanism that made
   it moot. Close with the reason, not silently.
3. **Is it actually a BUG?** This is the user's grey zone. The distinction that matters is not
   the word in `type:` — it is **what a user experiences**. If FPC/CPython/gcc accepts
   something pxx refuses, or pxx produces a wrong value, that is a **bug** however it was
   filed. "Feature" reads as optional and gets deferred forever; a mis-typed bug is therefore
   a ranking error that compounds. **Re-type it and say why in the ticket.**

**Triage is READ-ONLY and does not need the A/P slot** — compiling a repro touches no shared
file. A fix found by triage DOES need the slot; queue it rather than taking it.

**Never re-type or close from the title.** A title names the reporter's encounter, not the
boundary; several here have been wrong twice. Re-measure, then edit the body AND the
frontmatter `summary`, since the summary is what the board renders.

## Check +21h — one red triaged, pin deliberately held, all three lanes running

**Nobody blocked.** frank3 has the A/P slot and the import ticket in `working/` (two commits
landed: `3284c881d` record which language an import was written in, `6fba42d69` an import can
name another language by extension). frank2 on the A/P/C feature triage. plexus-T shipped both
guards (`e3eec52dd`) and is on the coverage-visibility fix.

**Watcher UP**, tested through `6fba42d69830`.

**PIN HELD, deliberately.** Two `compiler/**` commits sit past v363's base, both frank3's
in-flight refactor. Pinning mid-refactor is churn — nothing is blocked on the pin, no lane
builds on it right now (frank2's triage compiles repros, and it should use a HEAD build for
"is it already solved"), and frank3 will land more within the hour. **Pin at its next
milestone, together with whatever the red fix brings.**

### The red, triaged — and the stub's title named the wrong test

`regression-test-core-test-asm-ifdef-multiarch`: the job covers **two** sources.
`test_asm_ifdef_multiarch.pas` is FINE — compiles and runs clean (42, exit 0) on both v363 and
a fixedpoint build at HEAD, and **its success line is what the stub captured as the "log
tail"**, which is what makes the stub read as if that were the failure.

The real failure is `test/test_asm_att_reject.pas`, a **compile-time negative test** the
Makefile asserts with `!`. frank2's `76b6fb7f1` made `{$asmMode att}` accepted on purpose,
moving the refusal to an actual `asm` block — so the negative test now compiles and the
assertion fails. **Fix belongs in the test** (re-point at an AT&T `asm` block, still refused),
not the compiler. Routed to frank2; it is a `test/**` edit and needs no A/P slot.

**Recurring class, second instance today of the same surface:** a feature makes its own
refusal test compile, and `gate.sh quick` cannot see it because these live in `test-core`.
**When a feature relaxes a refusal, grep for the `_reject`/`_fail` test naming it and
re-point the recipe in the SAME commit.** Both of today's `test-core`-only catches were the
gate working as designed, not a gate that needs widening.

### From Track T, and it changes what a green means

**Zero full-tier runs in four hours; cross coverage is currently nil.** 76 testable pushes
since the last full tier (`9bfb7fcfac03`, 10:31Z), median interval 1-4 min, native run ~4 min,
full run ~21 min. Pushes arrive faster than a fast verdict completes, so the watcher is never
idle and every idle-only phase (full matrix, pin verify, fuzz) is **never scheduled** — not
aborted. `--status` says UP and is CORRECT: it measures whether commits were tested, and they
were, at native. **So the fleet reads as covered while no cross target has seen the tree since
10:31Z.** `a54259aab` and `354f734c1` both have native GREEN and neither has been near
i386/arm32/riscv32.

Approved T's separable fix: make `--status` and the tstate report say *"no full-tier verdict
for N hours"*. T's own argument is the durable one — *a property that holds only because one
agent remembered to warn another is a habit, not a property.* Scheduling trade filed
separately (`bug-t-the-push-rate-starves-breadth-coverage-entirely`, p60).

**No quiet period called** — the refactor and the triage outrank closing the gap this hour, and
the triage pushes little so the backfill should get a window on its own. Call one if a full
tier has not run by end of day.

**`/tmp` guard split routed:** C (12) and P (5) now; **N (14) and B (6) parked with the reason
written in** — N on the user's deferral, B unstaffed. An unrouted item with no stated reason
reads as an oversight.

## Check +22h — the import cascade routed, both idle workers dispatched, pin held again

**Nobody blocked.** frank3 holds the A/P slot, still on the reduced compiler
(`working/feature-a-build-a-reduced-compiler-...`). frank2 and plexus-T were both idle and
are now dispatched. Watcher UP, tested through `b26e49830a73`.

### The 12-job cascade, and the auto-filed ticket named the wrong commit

`regression-cascade-4e27dc2be114` (p70): 12 `test-core` jobs red since 14:43Z, STILL-RED at
`b26e49830` (15:19Z) — six tk examples and six nilpy tests, all NilPy sources. One cause, and
it is **intended behaviour**: frank3's `e1109d7bc` made a bare NilPy import resolve to Python
only, so every test still spelling `import tkinter as tk` now fails with the compiler's own
remedy printed in the diagnostic.

**The ticket's bad sha is wrong and its cause line is wrong.** It names `4e27dc2be1`, which is
**docs-only** (three markdown files) and cannot break a build, and guesses "likely a broken
build or harness event". The bisect attributed to the wrong end of the untested range
`48a60d096..4e27dc2be1`. *A cascade whose bad sha touches no buildable file is a strong tell,
and it is cheap to check with one `git show --stat`* — flagged to T as a possible guard.

**Routed to frank2 under Track P, re-tracked off T.** The watcher files cascades under T;
T owns the tool, never the bug. The fix is in the tests, not the compiler — the user
pre-approved this exact cleanup when taking the decision (*"there may be tests relying on
this, in which case we should rewrite the test"*). Told frank2 not to weaken the rule to make
them pass, to verify per job rather than sed the set, and that the two-imported-bases
negative test may have had its assertion changed by the new rule — third instance today of
"a change makes its own refusal test compile".

### Pin v364 was taken on the red tree

`pin.log` v364, base `4e27dc2be1` — inside the red range. Not bad in v362's sense (nothing
miscompiles; the semantics are the intended ones) but **`$(PXX_STABLE)` now carries the new
import rule with the tests un-updated**, so anything measuring against the pin rather than a
HEAD fixedpoint is standing on that. Both workers told. Not taken by me.

**PIN HELD again, deliberately** — pinning while 12 jobs are red buys nothing, and frank3 will
land more of the refactor. Fold frank2's green and frank3's next milestone into one pin.

### Breadth: the gap is now the tool's own line, not a person's

    breadth — newest full tier is 5h old, 46 testable commit(s) behind

That is T's `8af5acb7f` reporting the thing it was built to report. Dispatched T to
`bug-t-the-push-rate-starves-breadth-coverage-entirely` (p60) with one instruction: **do not
schedule a full tier this hour** — 12 jobs are red on purpose, so a 21-minute run would spend
itself confirming a known headline. **Call the quiet period once frank2 reports green**; cross
targets have seen nothing since `9bfb7fcfac03` (10:31Z) and that backfill is the real coverage
event of the day.

## STANDING RULE (owner, 2026-08-19, third restatement) — float accuracy is low prio BY DEFINITION

*"compiler syntax, segfaults, etc, all prio. floating point, especially when 'mostly ok'
(apart performance or insignificant digits), very low prio. by definition."*

**Rank the mechanism, never the datatype.** A wrong-value-at-scale, a saturation, a segfault,
a wrong signature or a control-flow bug is a normal bug at its normal prio even when every
variable in it is a `Double`. Only *accuracy* — ulps, rounding, last-digit formatting,
subnormals, range at the edges — is de-ranked. Today's writer cluster contained both kinds
under one grouping, which is how it got worked.

**Two doors bypass the prio field, and both are the coordinator's to close:**

1. **A red job is worked at the priority of being red**, not of its subject. NilPy's
   `.expected` files are generated from CPython, so an ulp move is a CI red. Until
   `meta-float-accuracy-policy` (Track U, raised to p60) is decided, de-ranking cannot stop
   the flow — the tests can re-summon it at any prio.
2. **Cluster grouping.** `TRIAGE-backlog-shrink.md` cluster 2 bundled three float writer
   tickets as low-hanging fruit, and "cheap and related" beat "low prio". That cluster was
   built here. **When assembling a cluster, check no member is de-ranked by a standing rule** —
   a cluster is a scheduling decision that the ranker never sees.

## Check +22h, part 2 — two workers disconfirmed the coordinator, both correctly

Both corrections came from workers checking a claim I had asserted from something adjacent to
it. Recording them together because it is one pattern, not two incidents.

### frank2: half the import cascade was NOT a test bug

I routed all 12 jobs as "rewrite the tests", from the diagnostic text. frank2 fixed six
(`630dc7da5`, quoted spelling, each verified against its exact Makefile assertion) and
**refused to rewrite the other six**: `lib/pcl/tkinter.pas` was written to BE Python's tkinter
and says so in its own header, naming `lib/rtl/re.pas` and `configparser.pas` as precedent —
both on the curated `PyRtlUnitServesPython` list. `tkinter` is absent only because the list was
swept from `lib/rtl` and tkinter lives in `lib/pcl`. Rewriting the examples would show a
spelling no Python source contains and put NilPy's GUI surface out of reach of unmodified
CPython code. Filed `bug-n-tkinter-is-missing-from-the-python-serving-unit-list` (A, p70),
**measured on a fixedpoint build then reverted** — routed to frank3, which holds the A/P slot.

**The best finding in it:** `test_nilpy_two_imported_bases_fail` was satisfying its leading `!`
at the *import wall* rather than at the refusal it exists to assert — one missing grep away
from passing while asserting nothing. General shape: **a negative test with no paired grep
asserts only "something went wrong".**

Also: frank2 hit the no-full-suite hook and **did not ask me to launder it** — correct, since
`PXX_ALLOW_FULL_SUITE=1` is gated on the user asking and a peer cannot supply that. It ran the
Makefile recipe lines directly instead and said so.

### plexus-T: "the watcher is never idle" was wrong by 8x, and I had carried it

The roster's own +21h entry stated it. Re-measured at HEAD: **idle 54% of the window, ~2.8h,
about 8x what one full tier needs.** Idle was never scarce; a *contiguous* window is.
**Breadth was not starved by pushes — it was queued behind an unfinishable item:** branch 2
(pin verify) sits above breadth deliberately and asks for ~21 contiguous minutes, idle arrives
in ~5-minute slices, every abort discards 100%, so `pin_verify_due` never goes false.
Confirmed cleanly — pin verify retired and breadth started within minutes, push rate unchanged.

Approved shapes **2 + 4** (resumable phases incl. pin verify; bound how long one unfinishable
phase may hold idle). **Shape 1 closed as measured-wrong**, with the number recorded so it is
not re-proposed. Also shipped: `8ec77190c`, a cascade ticket now names its RANGE — structural,
because `bisect_step` skips cascades by design, so a cascade's `bad` is *always* just the upper
bound of an untested range (17 commits -> 3 on the live incident).

**T's own pushes preempt T's own breadth** (`tools/**` is correctly testable) — it killed the
first breadth run in 5h13m at 207/2765 jobs by pushing its own fix. Filed rather than left as
a habit.

### The pattern, and it is mine

Three times today I verified one thing and asserted its neighbour: the cluster-2 file set, the
/tmp grouping, and now the cascade routing. **The workers caught all three by checking what the
artifact was written to BE before acting on what it looked like.** That order — read the
target's own header, then edit — is the whole difference.

**PIN: v364 is RED at full** (first pin verdict since v354), all deliberate import reds. Still
held. Retake once frank3 lands the tkinter one-liner; three compiler commits already past
v364's base fold into the same pin.

## STANDING: Track F = floating point (owner, 2026-08-19)

The owner assigned the letter after stating the rule four times without a marker to carry it:
*"track F is assigned to floating point. that's a clear marker and clean instruction."* Then
broadened it the same hour: *"this implies both floating point math and formatting issues."*

**F is a work-tag, not a file-lane** — O/E/S/M's shape. Tickets carry both letters (`B+F`,
`P+F`, `A+F`, `N+F`, `O+F`, `U+F`); the file-lane still decides who edits what and which gate
applies. `track_matches` is a substring test with `A+B` as precedent, so a `B+F` ticket answers
both `--track B` and `--track F` — the multi-track spelling the owner asked about already
worked and needed nothing.

**Scope:** ulps, rounding, subnormals, edge-of-range, fast-vs-exact tiers, float type
precision, the whole rendering side (`Write` of a real, `FloatToStr`, digit counts, exponent
form), and float-subject perf. Today's `WriteFloat` cluster would have been F end to end,
including the bad pin it produced — it is the drain the letter exists to stop.

**Escape rule, and it MOVED when the owner broadened F:** a badly *rendered* float is F even
when grossly wrong, because rendering is the subject. What is never F is a defect whose subject
is the MECHANISM and whose float content is incidental — a crash, a hang, a wrong signature, a
control-flow bug living in float code, or a **missing** function a working program calls. When
it is a close call it is NOT F: this folder is invisible by design, so mis-tagging toward F is
how a real bug disappears.

19 tickets in `devdocs/progress/float/`, unscanned by `ready`/`next`. Verified zero genuine F
items remain visible in any lane's queue (three near-misses checked by hand and correctly left:
methods on int and float, an extended *slice*, an inliner pass covering floats and records).

**Parking is not self-sufficient** — `bug-t-a-one-ulp-move-turns-the-fleet-red-and-outranks-its-own-prio`
(T, p45) stays in the ACTIVE backlog and is deliberately **not** F: its subject is the
scheduler, not the arithmetic. A red job is worked at the priority of being red.

Tooling gap routed to T: `--track F` is not yet an argparse choice and `float` is not in
STATUSES. Addressability only; the parking already works.

## Check +23h — tkinter landed, the cascade split in two, pin sequencing set

frank3 landed the tkinter list fix (`047bb8cc3` + `b47ab6f3f`, ticket in `done/`, fixedpoint
converged, quick green) and is back on the reduced compiler. frank2 interrupted for the second
half. plexus-T on breadth shapes 2+4 plus registering Track F.

### The cascade was TWO opposite answers in one directory

`examples/tk` holds seven jobs that must **not** be rewritten and two that **must**.
`hello.npy` and `widgets.npy` say `import tk` — that is `lib/pcl/tk.pas`, the Tcl/Tk binding
`tkinter.pas` is built on, and **CPython has no `tk` module**, so the argument that saved the
tkinter examples does not apply. frank3's test is the reusable one: **could a Python program
have written that import?** `tkinter` yes, `tk` no. Routed to frank2 with that framing, because
"examples/tk is red" reads as one cascade and is not.

**It was seven jobs, not six — and I had propagated the six.** Two sat in later Makefile blocks
(~1032, ~1036) than the tkinter block. Relayed a count without re-deriving it, which is the
exact thing the durable-facts list says not to do. Fourth instance today of asserting the
neighbour of something verified.

### Pin sequencing: TWO pins, against frank3's advice

frank3 proposed pinning only at the reduced-compiler acceptance milestone. Declined: **v364 is
RED at full**, and the two `tk` jobs also appear in Track B's `lib-test` (Makefile ~10222)
against `$(PXX_STABLE)`, so B's ground is red and **B is unstaffed to notice**. Pin once
frank2's rewrite lands, again at frank3's milestone. A pin is ~35s; leaving every lane on a red
pin for hours to save one is the wrong trade.

### The durable part of frank3's fix was the doc comment

It amended the list's **criterion**, not just the list: "when a new *lib/rtl* unit is written to
serve a Python module" described the sweep that caused the omission rather than the rule —
where a unit lives is not the question, what it is FOR is. Without that, the next `lib/pcl`
unit is missed identically. Fixing the instance leaves the class.

### Reduced compiler — the coupling findings are the valuable half

`PXX_NO_I386` (`91ca417b3`) and `PXX_NO_ARM32` (`ccef81c7c` -> `a771ff824`); four backends
omissible with the default build's fixedpoint intact. Both turned up real coupling: a
target-independent helper living in `ir_codegen386.inc` and called by arm32 across the backend
boundary, and the per-arch signal-runtime choice inlined three lines above the comment
explaining that this exact shape is why the other frontends shipped without the I/O lock. Both
normalised. The consequence — only the Pascal driver emits a signal runtime at all — filed as
`bug-a-only-the-pascal-driver-emits-the-signal-runtime` (p45) rather than fixed inline, since
it changes behaviour on every non-Pascal target. **This is the structural answer the owner said
the exercise was for**, not a side effect of it.

### CORRECTION (owner, +23h): the `tk` criterion was wrong — right answer, unsound reasoning

The owner challenged frank3's argument that *"CPython has no `tk` module"*. Measured rather
than adjudicated:

    python3 -c "import tkinter"       -> OK, /usr/lib/python3.12/tkinter/__init__.py
    python3 -c "import tk"            -> ModuleNotFoundError
    python3 -m pip index versions tk  -> tk (0.1.0)

**A PyPI package named `tk` exists.** A Python program can `pip install tk` and `import tk`.
And the owner's sharper form: `tkinter` needs installing on most distros (`python3-tk`), so
"needs installing" separates nothing either. Therefore **"could a Python program have written
that import?" answers YES for essentially any identifier** — anything can be published to
PyPI. The test classifies nothing. **I relayed it to both workers as reusable beyond this
case**, which is how a bad rule spreads faster than the fix it came with.

**The criterion that holds was already in frank3's own doc-comment fix**, one paragraph away:
**is this unit written to BE that Python module?** Each header answers it outright —
`tkinter.pas`: *"Named `tkinter` so `import tkinter` resolves through the unit resolver, like
lib/rtl/re.pas and configparser.pas."* `tk.pas`: *"Build a tkinter-shaped surface on top of
`TkEval` if you want familiar Python idioms."* Purpose stated by the unit, not inventory
claimed about CPython. Two standards in one session, and the weaker one travelled.

**The conclusion survives and gets STRONGER.** Because a PyPI `tk` exists, putting `tk` on the
Python-serving list would silently bind a real installed module's name to our Tcl/Tk binding —
exactly the failure the list exists to prevent. `hello.npy` / `widgets.npy` still get rewritten.

**The lesson is not "verify claims" — it is that a right answer teaches nothing about whether
the method was sound, and the method is what gets reused.** This one was reused within the
hour, by me, in writing, to two workers.

## Check +24h — pin v365 taken, csmith routed by move rather than by ticket

**Pin v365** (`cc20f7101`, base `9ea01645c`, sha256 `92a0997001…`). Clears every deliberate
import red v364 carried — frank3's tkinter list fix, frank2's fixture rewrite and the genuine
`import tk` rewrite — and lands the C intrinsic fix, the classes.pas shadowing fix, VLA via
alloca and five reduced-compiler omission defines on Track B/E's ground. Pre-lock check clean,
lock held ~40s, announced and released.

### A campaign ticket routed per MOVE, not per ticket

`feature-c-csmith-differential-fuzzing` looked half-owned. frank2 read it instead of guessing:
it is **correctly filed as C** — a standing campaign log (`status: done`, parked in `backlog/`
because it resumes by one command; 15 bugs found over five sittings, each filed into its owning
lane). What made it look ambiguous is that its two REMAINING moves fall on opposite sides of
the file-lane boundary:

- **axis 2** (cross targets under qemu) needs a `--target` pass-through in
  `tools/csmith_fuzz.py` — checked, the script has six flags and no `--target`. **T's file
  lane.** Routed to T, bundled with `bug-t-csmith-harness-reports-slow-as-a-timeout`, which is
  open against the same file: one visit instead of two.
- **axis 3** (csmith flags the defaults leave off) is `--csmith-args` on the existing script,
  zero T edits. **frank2's**, already running.

**The general rule, worth keeping:** a correctly-filed campaign ticket whose remaining moves
straddle a lane boundary does not want splitting — it wants each move routed as it comes up.
Splitting it is how two lanes end up editing one runner.

### Two findings banked from it

- **"Coverage thins where the generator is shy, not where the corpus is."** Both August
  findings were *a struct assignment used as a value*, a form hand-written C has no reason to
  produce, found from two angles. So the productive csmith flags are the ones emitting shapes
  hand-written code avoids, not more code.
- **Seed 90044 was filed `PXX_TIMEOUT` while both binaries finished and agreed** — pxx 18.2s to
  gcc's 6.9s, the wall-clock limit sitting between them. The report is the bug, but **fixing it
  buries a 2.6x ratio**: the case stops being reported at all. Asked T to record the ratio
  rather than only the pass. One seed is weak evidence; the point is a pattern cannot accumulate
  if each instance is discarded as a non-event.

### The reduced compiler: the SPEED half of the premise is false

frank3 measured what the owner assumed. Size −17.4% (2,789,936 B). **CPU time 45.9 ms vs
46.0 ms over 40+ hyperfine runs — identical**, and the wall-clock A/B reversed its own verdict
between rounds, i.e. noise reported as noise. Reason: the omitted code was never *executed* in
the full build either, it sits behind `TargetArch` arms a host compile never takes. **Removing
it removes bytes, not work. Footprint, not compile speed.** Relayed to the owner, since they
asked for the feature partly on "hence faster".

Acceptance chain runs clean (reduced -> full1 -> full2 byte-identical, and full1 byte-identical
to the repo's own self-hosted binary — stronger than asked). **frank3 itself refused to let it
be pinned as "acceptance passed"**: NilPy/Rust/Basic/Ada/Lua and riscv32/xtensa are still
compiled in, so it is a milestone, not a clearance, and must be re-run at each omission.

**Largest structural finding so far:** a backend is not two files. The shared `-O` pipeline in
`ir_codegen.inc` calls `UnifiedResidencyAssignA64` and `FloatPoolBoundaryAssignA64` by name,
and `symtab.inc` carries three full function epilogues emitting raw machine code side by side
(i386 as inline `EmitB($0F)` streams, arm32 143 lines, aarch64 173). Guarded, not moved; shape
ticket to follow. This is the answer the owner said the exercise was for.

**Third measurement fault of the session, same shape:** `{$UNITPATH ../lib/asmcore}` resolves
against the *working directory*, and frank3's scratch tree held a stale `lib/` — every trial
build linked a snapshot instead of the tree under test, producing working binaries and clean
error lists throughout. With the truncated FPC error lists and my own relayed job count, that is
three instances of **the rig answering a slightly different question, fluently**. Fluency is the
common factor: none produced an error, all produced plausible output.

## Triage pass by the coordinator (read-only, pin v365) — and my own fifth rig fault

Ran the mandate's question 1 (*is it already solved?*) against `stable_pinned` v365. Read-only,
no `make`, no slot — compiling a repro with the pinned binary collides with nobody.

**Seven A/P/C feature repros compiled. None stale, none already solved.** All four of the
headline refusals are intact and LOUD, with a diagnostic naming the missing feature:

    file of TRec            -> "file types are not supported (use TextFile for text I/O)"
    Copy(nested dyn array)  -> "nested element type not yet supported for dynamic-array Copy"
    operator +(Double,TCx)  -> "operator: cannot determine operand type"
    s.Trim                  -> "pxx does not implement Delphi's string helpers"
    read(TextFile, Char)    -> "reading into a Char is not supported yet"

**That is itself the triage answer to the owner's grey-zone question.** All five refuse a
construct FPC accepts, so by the "what does a user experience" test they are gaps — but they
refuse **loudly**, produce no wrong value, and name their own remedy. **A loud refusal of an
FPC-accepted construct is a feature gap; a silent wrong value is a bug.** That line is what
separates the 33 features from the ones that should be re-typed, and by it these five are
correctly typed as features. Nested-array indexing and bodied `cdecl` both RUN and print
correct answers, so nothing here is silently wrong.

`feature-cdecl-bodied-sysv-prologue` was already re-triaged today at v363 and its ticket is
accurate: direct Pascal calls agree with the internal prologue, which is why my repros printed
right answers; the real gap is `@PascalProc` into a cdecl proc-type with a float param, still
behind a loud `AN_ASSIGN` reject.

### My own rig fault — the fifth of the session, and I made it while warning others about it

I ran `fpc … -ot_fpc && ./t_cdecl2` and reported "FPC oracle agrees". **`./t_cdecl2` is the pxx
binary.** The FPC binary was built and never executed; I compared pxx against pxx and called it
an oracle comparison. Re-run properly, FPC does print the same values — so the conclusion
survives and the method did not. It was unearned when I stated it.

Same species as the other four today (`| head -60` capping an error count; `{$UNITPATH}`
resolving against a stale `lib/`; truncated FPC error lists; my relayed job count), and this
one landed **between** two messages in which I told workers to watch for exactly it.

**The countermeasure that would have caught it is not "check your commands" — it is: decide in
advance what a DISAGREEING result would look like, and notice when you never see one.** Two
independent compilers agreeing to the digit on a mixed float/int SysV boundary is a suspiciously
clean result; that suspicion is the tell, and it is available before the command is written.

## Check +25h — all three lanes running, nobody blocked, first GREEN since the import window

**Nobody blocked; no dispatch made.** frank3 busy (A/P slot, reduced compiler — `PXX_NO_NILPY`
next, the only frontend omission that moves size). frank2 busy (Track C, csmith axis 3).
plexus-T running (csmith `--target` + the timeout bug, bundled).

**Watcher: `d4b4e7e53104` GREEN (native)** — the first green since the import window, which
confirms pin v365 did what it was taken for. Predicted and now measured, rather than assumed.

**PIN HELD, deliberately.** One `compiler/**` commit past v365's base — `da53bbd26`, frank3's
eight frontend-omission defines. Nothing is blocked on it: the defines are inert in a default
build (fixedpoint converged in 1 round, default binary byte-count unchanged), Track B/E build
against v365, and frank3 lands `NO_NILPY` within the hour. Fold both into one pin.

### Breadth: the fix is live but has not yet had a window, and I am NOT calling a quiet period

    breadth — newest full tier is 6h old, 62 testable commit(s) behind  [STALE]

Shapes 4 and 2 both went live today (18:07:41 and 18:19:32). **Calling a quiet period now would
confound the only test that matters** — whether breadth reaches a window on its own, which is
the entire claim of the two shapes. So: give it one more check cycle. **If the next check still
shows zero full tiers, call the quiet period** and treat the shapes as not-yet-sufficient rather
than broken; T said plainly they make lower branches reachable, not fast.

Coverage risk is real and accumulating (62 commits with no cross verdict), so this is a bounded
wait, not a bet. `a54259aab`, `354f734c1` and everything since remain native-only.

## Check +26h — the breadth fix WORKED, and it immediately found 13 reds

**The bounded wait paid off and no quiet period was needed.**

    before (check +25h):  newest full tier 6h old, 62 testable commits behind
    now   (check +26h):   newest full tier 1h old,  2 testable commits behind

Track T's shapes 4 and 2 (18:07:41 and 18:19:32) reached a window on their own, which is the
claim they made. **Not over-credited: one window is not a rate**, and T is deliberately holding
its resume-stats reporting until there is one.

### And the first full tier in six hours came back RED — 13 jobs, four lanes

`regression-cascade-21f098e32a95`, full tier 17:28Z, wall 1230s. **`parent_tested == sha`, so
nothing was bisected: the "bad" commit is only the upper bound of a 261-COMMIT untested
range.** This is exactly the shape T's cascade-range fix was built for, on a range 15x longer
than the incident that motivated it.

    lib-test#…lib_mimic_xml_etree_elementtree.npy   Track B ground
    test-nilpy#… 10 jobs, seven of them cpyext      N
    test-riscv32#…test_cross_float.pas              A (cross; names tools/run_target.sh)
    tools-devtest#00                                T (T's own — hand over, do not fix)

**Routed to frank2 with the mandate question answered explicitly**, because it will come up
again: the standing mandate defers Track N *features and bugs*; a **regression is worked at the
priority of being red regardless of subject** — the same rule we settled for float. Triage all
13; fix where the cause is in A/P/C ground; if the cause is genuinely an N defect, **file it and
stop**. That is the line between honouring the mandate and letting a red rot.

**The first failure is not import-shaped**, which is worth saying because the last two cascades
were: the ElementTree job **compiles** (`ok:` line, 1758 procs) and then dies at runtime with
*"can only concatenate str (not \"method\") to str"* — a method-vs-bound-method distinction,
which smells like the callable-representation family. Whether all ten NilPy jobs share that
shape or split into two causes is the first question, and 13-in-one-sweep is ONE root cause
until triage proves otherwise.

**PIN HELD — and this time for a stronger reason than churn.** Four `compiler/**` commits sit
past v365's base (`da53bbd26`, `e6a14039a`, and carve steps `fd6ec21a3` + `832a42d02`).
**Nothing gets blessed over an unexplained 13-job cascade**, because a pin puts every lane on
that ground. Reassess when frank2 has attribution and frank3 lands carve step 3/3.

**Both workers were idle** (owner set a low autocompact threshold on both) and are now
dispatched: frank2 on the cascade, frank3 finishing the carve. frank3's `working/` lock is
correctly held on `task-a-carve-nilpy-lvalue-parsing-out-of-parser-inc`.

## OVERNIGHT 2026-08-19 — owner asleep, report due in the morning

Owner went to bed ~19:00 local and asked for a **report in the morning**. Standing plan, so it
survives a context loss:

**Wind down to a quiet cadence rather than stopping or fanning out.** Let the two in-flight
items finish — frank2's cascade triage and frank3's carve step 3/3 — then **do not dispatch
fresh parallel work**. The owner's stated position (2026-08-19, token budget): *"the overnight
stuff will also be a single track working. dual track all day will spend my tokens."* So after
the current items land, keep at most ONE lane moving and let the others idle. Idle is correct
here and costs nothing.

**Do not take a pin overnight unless a lane is blocked on one.** The pin is currently held over
the open 13-job cascade and that is the right state; blessing an unexplained red while nobody
is awake to catch a bad pin is the one thing that could poison every lane by morning. v362 is
the precedent.

**Track T runs unattended on plexus and needs nothing** — its breadth scheduling now reaches
windows on its own, so the matrix keeps sweeping without a quiet period being called.

### What the morning report must cover, in this order

1. **The 13-job cascade** — attribution over the 261-commit range, what it was, which lanes it
   touched, what is fixed vs filed. This is the headline; it is the first cross-target verdict
   in six hours and it found real breakage.
2. **Pin state** — whether it was safe to pin by morning, and what v366 carries if taken.
3. **The carve** — split 2 done or not, and the campaign's objective finish line
   (**183 Py* helper bodies / 504 sites remaining** — see the correction below; `PXX_NO_NILPY`
   compiling clean = carve complete).
4. **Breadth** — whether the full tier kept its cadence overnight, i.e. whether one window was
   a rate after all. T is holding resume-stats until there is one; do not pre-empt that.
5. **Corrections owed** — every survey error count relayed as a figure is a FLOOR, not a count
   (FPC skips its unsolved-forward pass when the module already has errors). Say so plainly if
   any number from today gets repeated.

Keep it short and lead with what changed, not with what was busy.

### Carve split 2 landed, and the finish line CHANGED SHAPE (2026-08-19, frank3)

`fd6ec21a3` verbatim copy → `832a42d02` folds → `2730e6566` delete the dead arms →
`86d2fe061` ticket resolved. `ParseLValueAST` in `parser.inc` 3145 → 2511 lines; the routine
now lives as `PyParseLValueAST` in `pyparser.inc`, dispatched on `PyExprMode`, **no call site
moved**. Fixedpoint converged in 1 round at every step, `make bootstrap` byte-identical,
`gate.sh quick` green at each, seven NilPy repros picked to hit the folded arms.

**The number I relayed as the finish line was wrong in the flattering direction, and frank3
corrected it against its own earlier figure.** Measured with one script on both sides:

    before the carve   183 Py* bodies, 569 sites
    after split 2      183 Py* bodies, 504 sites

**Moving the single most dialect-forked routine out of `parser.inc` removed ZERO Py* helper
bodies** and 11% of the sites. So the remaining distance to `-dPXX_NO_NILPY` is **not more big
forked routines — it is 183 Py\* helper bodies still sitting in `parser.inc`.** Split 3 must
target helper bodies; another fork site will barely move the metric. (183/504 vs the opening
176/426 is the same population under a different counting rule — the before/after PAIR is what
is comparable, both from the same script. Do not mix the two figures.)

Two things the three-commit shape exposed that a single commit would have hidden: a Pascal-only
"a value of this type has no members" refusal that was dead in a NilPy-only copy, and
`NilPyUserCode` reducing the **opposite** way on the two sides (to `isNilPy` under `PyExprMode`,
to `isNilPy and CurrentUnitIdx < 0` without it). Every `isNilPy`/`NilPyUserCode` arm was left
intact in the Pascal original.

**Open gap, routed not closed:** the whole-suite `.npy` sweep that ticket's Gate line asks for
was NOT run — the hook refuses it, CLAUDE.md supersedes ticket Gate lines naming long local
suites, and only the owner can authorise `PXX_ALLOW_FULL_SUITE`. **A carve-out is a narrowing
change, so NilPy breadth on these three commits rests entirely on Track T**, which is the
normal division of labour and not an escalation — all four shas are on origin/master and T is
UP (breadth 1h old, 3 behind). Raise it in the morning report as a thing the owner may want to
sweep explicitly before a pin, not as a blocker.

**riscv32 `test_cross_float.pas` — frank3 says NOT `da53bbd26`, and flags it as reasoning:**
the eight defines are omission defines defaulting to OFF, nothing in the tree sets any
`PXX_NO_*`, so a default cross build sees byte-identical source; the riscv32/xtensa increment
was parked rather than landed, so no target-selection code changed. **That is an argument, not
a measurement** — treat it as a prior for frank2's triage, and send it back to frank3 to bisect
properly if the triage does point at a define.

### The 13-job cascade is EXPLAINED — four causes, and all four predate the pin (frank2, `7daee90ac`)

The "one root cause until proven otherwise" heuristic held for nine jobs and then broke. Every
job reproduced by hand at HEAD. Breakdown: **6** cpyext jobs = the import rule colliding with a
real C extension module, filed to **Track U** and deliberately NOT fixed; **3** = ordinary
missed migration to the quoted import spelling, fixed green; **2** = the callable family, bisected
to `9bbbbef6c`; **1** = riscv32 float rendering, filed `A+F` with options; **1** = `tools-devtest#00`,
handed back to T.

**The coordination fact I checked and frank2 did not state: every one of those causes is already
INSIDE pin v365.** `9bbbbef6c`, `9bfb7fcfac03`, `7bebd63fa` and `354f734c1` are all ancestors of
`cc20f7101`. The five held commits — `da53bbd26`, `e6a14039a`, `fd6ec21a3`, `832a42d02`,
`2730e6566` — caused **none** of the 13.

**So the reason I was holding the pin has dissolved, and I am holding it anyway for a different
and better one.** "Nothing gets blessed over an unexplained cascade" no longer applies: the
cascade is explained, and explained as *already-blessed ground*. Withholding v366 protects
nobody from these four causes, because every lane is building on them right now. What still
argues for waiting is narrower and real: **the carve is a narrowing change and its NilPy breadth
is unswept** (T's full tier had not reached `2730e6566`), and `quick` structurally cannot see it.
That is the whole remaining case for waiting, it is about the carve and not about the cascade,
and it expires the moment T sweeps those shas. **Do not carry "the cascade" into the morning as a
pin blocker — it is not one.**

### Make this standard: when a cascade straddles a pin, ask which side each job builds with FIRST

frank2's most valuable finding, and it inverts the obvious reading. The `lib-test` job is **not a
regression in the range at all**. It builds with `$(PXX_STABLE)`. The pre-range pinned binary runs
it GREEN; a compiler built from source at the range's own **last-good** sha `9bfb7fcfac03` fails
it, and so does one built at `7bebd63fa`, the commit that ADDED the test. The defect was in the
source the whole time and the pin was lagging behind it — **`cc20f7101` EXPOSED it, it did not
cause it.**

**So a pin commit will always look like a mass regressor and never be one.** It changes which
binary the B/C/D-lane jobs build with, so it converts a backlog of already-present source defects
into simultaneous red. Reading a range across a pin boundary without asking which side each job
builds with attributes a pile of old bugs to whoever happened to pin.

The corollary is worth the owner's attention in the morning: this is an argument for pinning
**sooner and smaller**, not for pinning carefully. The longer a pin lags, the larger the tranche
it exposes in one go and the more it looks like a catastrophe.

### Open after the triage — ten of 13 filed, three green

- `decide-nilpy-import-rule-vs-a-cpyext-extension-module` (**U, prio 75**) — the headline. The six
  cpyext tests import `hello_ext`, which is CPython's own spelling for a C extension, and
  `test/nilpy_units/hello_ext.pas` IS the extension module (it pulls `./hello_ext.c` with its
  PyMethodDef table and `PyInit_hello_ext`). Rewriting them to the quoted spelling would make them
  green **by deleting their subject**, in the exact tests whose subject is CPython compatibility.
  frank2 recommends keying bare-importability on `PyInit_<name>`. **This one needs the owner.**
- `bug-n-a-callable-value-reaches-a-str-parameter-and-renders-as-bound-method` (N, 70) — bisected
  to `9bbbbef6c`; `f(c.m)` where `f(s: str)` was a compile error and now prints
  `<bound method at 0x…>`. Five builds in a throwaway clone seeded from the pinned binary, never
  in the shared checkout — correct method.
- `bug-a-riscv32-cross-float-output-no-longer-matches-x86-64` (**A+F**, 60) — riscv32 reduces float
  depth, so those Doubles are Singles and render in the Single form. The values agree, the widths
  do not, and the one line exact in both still matches. **The new rendering may be the correct one
  and the defect may be the test's assumption** that a depth-reduced target is byte-comparable
  with x86-64. Filed with options rather than fixed, which is right.
- `bug-a-c-driver-omits-rtl-stubs-for-an-imported-pascal-unit` (A, 55) — any Pascal unit whose body
  touches a managed string dies at import from C with "call to a runtime stub that was never
  emitted"; also why the AnsiString-result refusal is landed but not exercisable.
- `tools-devtest#00` → plexus-T (`twatch_host_epoch_devtest.py`, one case, 44 others pass).
- `feature-c-import-a-pascal-unit-under-a-mangled-name` core landed self-host green (`1b3ea136b`);
  ticket stays in `working/` with §3 path collisions, §6 the bare-name experiment and `test/` cases
  written down.

**Refinement on the straddle rule (frank2, after the fact):** they are TWO questions and asking
only one leaves you half-informed. *Which binary does the JOB build with* tells you whether the
range is even relevant. *Where does the CAUSE sit relative to the pin* tells you whether holding
the next pin buys anything. The first is the one people ask; the second is the one that decides
a pin. Both workers stood down clean — tree clean, nothing unpushed, master level with origin.

### `tools-devtest#00` fixed by T (`93db54159`) — and BOTH hypotheses I attached were wrong

The case `changed-hardware-opens-a-new-epoch-and-closes-the-old` assigned a **literal**
`"Intel(R) Core(TM) i7-6700 CPU @ 3.40GHz"` as "the other machine" and asserted
`record_host_epoch(...) is True`. That is a hardware change on every box **except** an
i7-6700 — and borg, which the case's own docstring names as the `from` side, is one. Run
there, `record_host_epoch` correctly returns False and the case fails while the code under
test behaves exactly right. Sentinel is now `"Not-" + host_hardware()["cpu"]`, different by
construction on every host. Reproduced by pinning the live cpu, not argued.

**So it was neither "a defect in the epoch logic" nor "xeon being retired".** My retired-host
hypothesis was the right *question* and the answer was no: the case builds a fresh temp tree
per run and `"xeon"` there is a bare string label — no fleet history is in reach. What it
reads is the **live box**, which is where the host-dependence entered.

**And I cost T a pass by relaying the wrong line.** The fingerprints I quoted
(`hardware fingerprint changed for xeon A -> B`) are what `record_host_epoch` prints on its
**success** path; they cannot identify the failing assertion. **Relay the
`FAIL <case>: <message>` line, not the output near the failure.** Third instance this session
of forwarding surrounding output as if it were the finding — written up in working memory.

**A real adjacent defect, found on the same look and fixed (`f5cba8ad3`):** `record_host_epoch`
took **two independent readings** — `host_hardware()` for the stored fields, `host_hardware_fp()`
for the fp. `host_hardware()` re-reads governor and turbo on every call by design while caching
the rest, so a **governor tick between those two lines** stored an epoch whose own fields do not
produce its own fp. Every later publish then compared live hardware against a fingerprint no
reading could reproduce, and minted a spurious "earlier rows are not comparable" epoch **over a
cpufreq transition**. One reading now, guarded by a case that returns a different governor on
each call. T is explicit that it has **no evidence this is what the devtest hit** — two real
defects, one look, kept separate. It would have corrupted the epoch series in the field.

**Operational trap worth remembering:** T reverted the fix, saw the guard fail, restored the fix
— and it still failed. Stale `tools/__pycache__/*.pyc`: **the traceback displayed the current
source line while executing the old bytecode.** If a result contradicts the source in front of
you, `find tools -name __pycache__ -prune -exec rm -rf {} +` before believing it. Not live in the
watcher clone (pycs timestamp-invalidated and matching) — it bites when a file is rewritten twice
in quick succession.

**Also landed, green and pushed:** csmith `--target` (`6edac13fd` and parent). A cross run now
**refuses to report a comparison it did not make** — with no data-model-matching gcc it prints
`NOT CHECKED: agreement with gcc, and the slow ratio` instead of an N/M-agreed line counting
comparisons nobody ran, and `PXX_SLOW` returns early because a ratio against a native oracle
measures qemu rather than the compiler. `EMU_TIMEOUT_FACTOR` **12 → 30, as a measurement not an
allowance**: seed 90044 under qemu-aarch64 takes 187.96s (gcc -O0 native 12.92s, pxx -O0 native
46.27s), so the old 180s floor was killing a legitimate run as a hang.

**Pin status unchanged and now confirmed from T's side: the unswept carve through `2730e6566` is
the only thing holding it.**

**CONFIRMED by measurement, not by agreement (coordinator, this box):** `/proc/cpuinfo` here says
`Intel(R) Core(TM) i7-6700 CPU @ 3.40GHz` and `hostname` says **borg** — so T's sentinel-collision
theory does cover the failure. Established both directions on this box: the pre-fix
`twatch_host_epoch_devtest.py` (from `93db54159^`, run in a scratch copy) FAILs
`changed-hardware-opens-a-new-epoch-and-closes-the-old`; at HEAD all cases pass. So the retired-host
and two-reading mechanisms stay ruled out and `93db54159` closes it.

**And the harness has a reportability defect that explains the bad relay better than carelessness
does.** The failure prints as `FAIL changed-hardware-…:` with an **empty message**, and the very
next line of output is `twatch: hardware fingerprint changed for xeon (08a191cf19ad -> a1302d0ee045)`.
A reader who takes the line after the colon gets the wrong subject **and the format invited it** —
the FAIL line offers nothing, so the nearest line is adopted. Worth T's attention: a FAIL with no
message is what turned one relay into a wasted pass. The discipline (quote the FAIL line) stands;
so does "and if it is empty, say so rather than substituting the next line".

### The empty FAIL line is fixed structurally, not case by case (T, `4d6e626cb`)

`tools/devtest_report.py:fail_detail(exc)` — an author's message wins; with none it reports
`<file>:<line>: <the assert's own source>` from the **deepest** traceback frame (the assert, not
the runner that caught it), prefixed "with no message" so the line states what it is instead of
implying a reason. Wired into all six runners that printed a raw exception; all six green.

    FAIL changed-hardware-…: AssertionError with no message —
    twatch_host_epoch_devtest.py:120: assert twatch.record_host_epoch(clone, "xeon") is True

**The design argument is the transferable part: a hand-written assert message can drift from the
assert it describes; the assert's own source text cannot.** That is why this went in as a shared
renderer rather than as a message written onto the one failing case.

**And the guard is end-to-end, with its non-vacuity proven by removal.** `devtest_report_devtest.py`
breaks the real changed-hardware case in a scratch copy, runs the harness as a subprocess, reads the
FAIL line back, and asserts it carries the assert **and does not contain "hardware fingerprint
changed"** — so the exact substitution my relay was forced into is now a red check. Neutering
`fail_detail` to `str(exc)` turns 6 of 12 red, every end-to-end one among them. Same discipline as
verify-by-removal on the alias fix: a guard nobody has seen fail is not yet a guard.

**T's own correction, worth keeping because it is the harder kind:** it called the retired-host
mechanism "ruled out by measurement", then noted it was never in contention for a reason readable in
the case's first six lines — the case builds a fresh temp tree per run, so no stored fingerprint is
reachable. Ruled out by measurement after spending a pass, where reading would have done it before.
Right answer, more expensive method than needed, said out loud.

Pushed and green tonight from T: `93db54159`, `f5cba8ad3`, `6edac13fd` and parent, `4d6e626cb`.
Watcher is mid-tier and deliberately not starting a contending sweep.

## Check +27h — pin held on a MEASURABLE reason now, one worker dispatched

**Pin: 6 `compiler/**` commits past v365 (`9ea01645c`) — `da53bbd26`, `e6a14039a`, the three carve
steps, `5da541ca8`. Step 2's mechanical rule says pin. I am not pinning, and the reason upgraded
from a judgement call to a fact:** `bug-a-make-revert-the-documented-pin-brake-does-not-fire`
(A, p60). `make revert` restores from per-version `vN` binaries this tree stopped keeping at
`929fa707c`, so it fails with `Binary ... missing`. **The documented recovery from a bad pin does
not work**, and the v357 incident recovered only because the operator knew the commit-revert route.
With the owner asleep, "recoverable" is doing all the work in "pin now, revert if wrong" — and it
is false. Six commits is a small tranche; it keeps until morning.

Note this reason is strictly better than the two before it (unexplained cascade → unswept carve →
this): it is checkable by anyone, and it names its own expiry. **When the brake fires, pin.**

**Dispatched frank2 → that ticket, with the A slot granted** (frank3 is off A since the carve, so
sole-A holds; the ticket touches the Makefile and `stable_linux_amd64/**`, not `lexer.inc`/
`parser.inc`). Asked for three things beyond the fix: exercise the brake in a scratch clone rather
than argue it, grep for other emergency-only consumers assuming `vN` exists, and **do not pin** —
the pin is the coordinator's and it is a morning decision. Told it to bank and stop if it grows.

One lane running is the correct overnight level, not zero — the owner's position is that the
coordinator/worker split exists so work continues while they sleep. frank3 stays down (its status
reads `shell`, i.e. working/not idle — do not ping). frank2's `feature-c-import…` lock stays in
`working/` untouched.

**Queues, all six lanes read:** every lane has ready work; nothing is blocked anywhere. Heads —
A `refactor-a-one-signature-record-for-every-callable-carrier` p66 (the callable-carrier root-cause
refactor, and tonight's `bug-n-…bound-method` p70 is another instance of exactly that family — worth
the owner's attention as a root-cause candidate rather than fixing the N symptom); P
`feature-pascal-corpus-fpc-testsuite` p65; N the callable bug p70; B `feature-b-a-fourth-corpus…`
p55; C `feature-c-csmith-differential-fuzzing` p65; T `regression-cascade-21f098e32a95` p70 (now
triaged and mostly filed out — that entry should shrink).

**`urgent/` holds exactly the three tickets frank2 filed tonight**, correctly: the U decision at
p75, the callable bug at p70, the riscv32 float at 60 (`A+F`).

**T: UP, native green through `a15cb05fa`. Breadth reads 2h old / 10 behind — that is a full tier
in progress, not a slip; do not read it as a regression.**
