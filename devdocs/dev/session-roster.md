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

Not a vibe — a measurement, and the bump has a name. As of tonight the third-party
ladder stands at **6/48 compiled**, with the remaining blockers split:

| blocker class | files |
| --- | --- |
| missing module | **8** (4 behind `decide-xml-etree-…`) |
| **language** | **32** |
| — of which **`yield`** | **18** |

**`yield` IS the bump.** It is more than every missing-module row combined, it is not
blocked on the boxed-def decision, and the generator engine is already built and proven
for Pascal (`slgen.pas`, stackless, working). Landing it is the single highest-value
thing that can happen this week.

**How to report it, every time:** re-run `tools/nilpy_ladder.py`, **name the sha of the
compiler binary used**, and report **past-a-wall separately from onto-the-next-wall**.
The headline count can sit still while a great deal moves — it did all of 2026-08-18.
Never quote an earlier scan as current; every table is a snapshot.

### The one dispatch rule that must not be broken

**`feature-nilpy-yield-outside-a-for-loop` (p75, top of N) goes to a FRESH session only.**
Its failure mode is **silent stack corruption** in `PyEmitParamSpills`, not a compile
error. Handing it to a long-running session because `next` ranks it first is precisely
what the ticket's banner exists to prevent. The diagnosis is banked so a fresh session
starts from it rather than rediscovering it. **First thing a fresh worker gets.**

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
