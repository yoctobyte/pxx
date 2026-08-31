# pxx — agent guide

PXX / pascal26: a self-hosting Pascal-dialect compiler (FPC-seeded), with its own
RTL, multiple backends (x86-64 default IR; i386 / aarch64 / arm32 / xtensa /
riscv / wasm32 cross targets), and C, Nil-Python, Rust and Zig frontends.

**This file is RULES ONLY.** The evidence, incidents and reasoning behind them —
nearly all of it measured — live in **`devdocs/dev/handbook-rationale.md`**.
Look a thing up there when you need the *why*; do not read it. It was this file
until 2026-08-31, when 72KB of instructions-plus-history was cut to rules,
because every session paid the history at startup.

**Never cite a big reference file as "read this".** Name the section and its
cost. The three that were wrong cost ~470k tokens between them, obeyed literally.

## The goal — what makes work on-target

**`devdocs/dev/the-goal-cross-cross.md`.** pxx runs under linux/bsd/minix/gnu/
windows/wasm, compiles **DOSBox** for such a target, and runs a **minimal system
with the compiler on it**. Languages × platforms, the product of both axes.
Two proofs, both real programs: DOSBox runs; pxx hosts itself somewhere that is
not Linux/x86-64.

**We do NOT chase FPC parity** — *"we just care for correct compiling pascal
code, not emulating every behaviour."* Real code compiling or running wrong is a
**bug**. FPC accepting what we reject is **compat**, ranked by how much real code
uses it. Us accepting what FPC rejects is **not a defect**. A differing
diagnostic is **deferred**. An observable no compiling program can reach is
**`rejected/`, never a low prio** — parking it at 10 keeps it in the ranker
forever at zero value.

## Umbrellas — the goal is the ranking

An **umbrella** is a GOAL: a real program that must work. `backlog-umbrella/`,
`type: umbrella`, top of a dependency chain.

- **Umbrella `prio:` is the only number a human sets.** Everything else inherits:
  `effective_prio` takes the max of a ticket's own prio and of everything it
  unblocks, transitively. Rate the goal, the chain follows.
- **Membership is an EDGE (`blocked-by`), not a folder** — so one ticket can sit
  under several umbrellas. The ranker takes the max. Wire it to all of them.
- **Grow an umbrella by ATTEMPTING THE TARGET, never by triaging the backlog.**
  Each failure names a ticket in the order it actually matters. What the attempt
  never touches was not blocking real-world usage.
- **An umbrella with no blockers means nobody has attempted that cell** — that is
  information, not missing paperwork.
- `next` will not hand you an umbrella; take something it blocks.

## Tokens are a constraint

**No timed callbacks, any track:** no `/loop`, no `ScheduleWakeup`, no cron, no
"check back in N minutes", no `sleep N; tail log`. A timed wake-up re-reads your
whole context to learn nothing. Background a job and let its completion be the
wait; `notify_when_idle` for a peer. Clear any you have — `CronList` is
per-session, so only you can. **Track T's watcher daemon is NOT affected**: the
cost is a model re-reading context, not a timer on a box.

**Peer-to-peer messages stay preferred** — bounded, and they carry a fact.

**Fleet size is the owner's token dial.** He starts sessions; you never raise the
count, and an idle session is idle on purpose.

**Work in GROUPS — a topic or a target, never a lone ticket.** `next` names the
ENTRY POINT; grep the backlog for its subsystem and pull the neighbours in first.
You cannot notice that eight tickets share one cause while holding one of them.
Say which group you hold; report by group. A genuinely isolated ticket is fine —
the rule is against not looking.

## Fix it, then note it

**You have the authority. Filing instead of fixing is the error.** Fix it, log
one line in `devdocs/progress/LOGBOOK.md` (`date | agent | file | what and WHY`),
move on. This retired *"document our bugs as a goal in itself"* (owner,
2026-08-31) — that directive produced 5035 tickets, 467 still open.

**The test is "can I fix AND verify this right now?"** — not "is it small?", and
no longer "can it change behaviour?". Code counts. A `.expected` counts. A rename
counts.

**A ticket is for work needing coordination, ranking or memory** — most often
because you cannot finish it now. Diagnosed something deeper than the session?
**Bank the diagnosis and park it.** Never microfix as a consolation.

**Four guards, all about verifying, none about permission:**
- **Land green.** Fixing on the fly does not suspend your gate.
- **Verified, not believed** — deleting code you *believe* is dead is still wrong.
- **Comment vs code:** if they disagree, one is wrong and you do not know which.
  Decide first. Matching a comment to broken code destroys the evidence.
- **No compiler-appeasement workarounds.** Hitting a compiler bug is the one case
  you do NOT fix locally: **leave the platonic code**, file the bug with a repro,
  `blocked-by:` it if you stay blocked. Renaming/reshaping/rerouting to pass
  today hides the bug. **No exception for self-hosting** — a change that breaks
  `compiler.pas`'s own fixedpoint is **REVERTED, not patched around**. Track B's
  `devdocs/dev/track-b-workarounds.md` (platonic library code that sidesteps an
  open bug with a revert-when-fixed lifecycle) is a separate deliberate pattern
  and is unaffected.

**A ticket's `summary` MUST be true** — it is the only part everyone reads, and a
stale one misroutes whoever reads it. Fix it in the same commit. Below the
summary is append-only history nobody must read. **Keep a new ticket to one
screen.** A finding whose value IS its length goes in a reference doc with a
one-line logbook pointer.

## Tracks — coordination lanes, not a taxonomy

| | lane | files it owns | gate |
| --- | --- | --- | --- |
| **A** | compiler core | `compiler/**` — AST, IR, symtab, backends, ABI, ELF | `make test` + self-host fixedpoint |
| **B** | libraries / demos | `lib/rtl` `lib/pcl` `lib/crtl`, `examples/**` | `make lib-test` / `make demos` |
| **C** | C frontend | `clexer` `cparser` `cpreproc`, C→IR, `lib/crtl` | C tests + self-host + cross |
| **D** | public docs | `docs/**` (prose only) | snippets compile against `$(PXX_STABLE)` |
| **N** | Nil-Python frontend | `pylexer.inc` `pyparser.inc`, Python→IR | `test-nilpy` + self-host + cross |
| **P** | Pascal frontend | `pasparser_*.inc`; **`lexer.inc` shared with A** | `make test` + self-host + cross |
| **R** | Rust frontend (X) | `rfront`, Rust→IR, `lib/rrtl` | Rust tests + self-host + cross |
| **Z** | Zig frontend (X) | `zlexer` `zparser`, Zig→IR, `lib/zrtl` | Zig tests + self-host + cross |
| **T** | tools & testing | `tools/*.py`, `pasmith*`, `tstate/**` | `testmgr --tier full` |
| **W** | website | the separate `~/pxx-website` repo | that repo's own |
| **U** | decisions | none | none |
| *tags* | **O** optim→A · **E** apps→B · **S** ESP→A/B · **M** Windows→A/B/T · **F** float→file owner · **X** experimental · **compat** | inherit the file-lane's | inherit the file-lane's |

- **One lane per session** by default; name it in full ("Track C (C frontend)").
  Don't invent letters.
- **Lanes are hints, not locks. THE SEPARATOR IS THE TOPIC, NOT THE FILE.** Two
  agents in one file is fine — git merges it. Two agents on one QUESTION is not:
  both diffs apply cleanly and no letter sees the collision. Ask "is anyone on
  this topic", never "is anyone in this file".
- **Shared internals are A's territory — ownership, not a lock.** Edit them when
  your ticket needs it. **Telling is not asking:** say what you are touching,
  name a window, proceed if nobody objects. Silence is not refusal. Coordinate
  by message for one thing only: **token/node numbering in `lexer.inc` /
  `defs.inc`**.
- **U is the decision lane.** Hit a design/intent fork you cannot settle from
  code, request or a sane default → file `decide-<topic>` (fork, options,
  trade-offs, your recommendation) and move on. Don't guess.
- **Land only green** where your gate is cheap; destabilising work goes behind a
  flag or lands incrementally, never on a long-lived branch.

### Per-lane facts a table cannot carry

- **A — pin with `make stabilize-fast && make pin` (~35s), never plain
  `stabilize`.** A pin blocks every other lane and the human while it runs.
  `stabilize` alone does NOT move B's ground; only `make pin` does, then commit
  `stable_linux_amd64/**`.
- **B / E — build with `$(PXX_STABLE)`, never rebuild the compiler.** A compiler
  or language gap → ticket in the owning lane.
- **T — owns the TOOL, never the BUG.** A compiler gap it hits → ticket in the
  owning lane. May improve its own tooling freely; its daemon writes ONLY
  `tstate/`.
- **S — ESP is not a Unix.** FreeRTOS gives tasks, not processes; 33 PAL entries
  refuse deliberately, so POSIX-shaped code meets `PAL_ERR_UNSUPPORTED` rather
  than a wrong answer. Primary target **xtensa**; riscv32 works.
- **F — low prio by definition**, parks in `devdocs/progress/float/`, which
  `ready`/`next` never scan. F is float math AND formatting, plus float-subject
  perf. **NOT F:** a crash, hang, wrong signature, control-flow bug that merely
  lives in float code, or a missing function a working program calls.
  *Rank the mechanism, never the datatype.*
- **N — NilPy is UPWARD compatible with CPython**, one direction. Accepting what
  CPython rejects is a feature (`devdocs/dev/nilpy-semantics-divergences.md`).
- **D — verify snippets by compiling them.** Never touch `compiler/**` or `lib/**`.
- **O — the levels:** `-O0` none · `-O1` debug-safe (intention, untested) · `-O2`
  the proven default · `-O3` experimental, **on track for `-O2`, it drains** ·
  `-O4` research, never assumed. **Both must be CORRECT** — `-O4` is speculative
  in value, never in correctness. **Trade-offs are a named flag, not a level**
  (`-Ofast`, `-Os`, `-funroll-loops` are sideways).
  **TWO gates, both required: PROMISE** (delivered value, measured — not
  opportunity inferred from an instruction census) **and PROOF** (Track T's full
  tier, not your own gate). **Promote ONE AT A TIME — the batch is not the sum.**
  **Do NOT build the dev loop's compiler at `-O3`.**
  Note: proof is defined as a full run with `skip_holes == 0`, which **seven can
  never produce** (no RDRAND) — see
  `decide-the-proof-grade-gate-is-unsatisfiable-on-the-host-that-does-the-sweeping`.
- **Claims discipline** — "self-host fixedpoint" (our binary reproduces itself,
  at the DEFAULT `-O` only) and "zlib matches the gcc oracle" (the program's
  OUTPUT matches) are DIFFERENT claims. Never conflate them in public copy.

### Design north stars

- **`devdocs/dev/ir-as-substrate.md`** — push generality down into the IR, keep
  frontends thin. Track A is the one gate and the one multiplier.
- **`devdocs/dev/the-substrate-is-ast-and-ir-not-the-parser.md`** — the
  counterweight: **share the AST and IR; duplicate the parser and lexer per
  language.** Normalise *within* a language, duplicate *across* them.
- **`devdocs/dev/normalise-dont-special-case.md`** — when a construct is
  reachable through two shapes, normalise rather than grow a second path; the
  second path is the one that stays broken. **Fixed one arm of a double case?
  Grep for the sibling before closing.**
- **`devdocs/dev/root-cause-over-microfix.md`** — a ticket reports a SYMPTOM and
  names a plausible cause, and 9 times in 10 the real fix is deeper. Reproduce,
  **vary the shape** to find the boundary, count how many mechanisms serve one
  concept (two is a smell, three is a design flaw). The overhaul is often the
  *smaller* job — it deletes cases. Measure by tickets-closed-per-change.

## Asking the owner is the expensive path

**Human attention is the scarcest resource here** — one owner, many agents. A
question does not cost you a minute; it costs the one thing that cannot be
parallelised.

**The test is REVERSIBILITY, not importance.** Reversible → do it and report. A
big reversible change is yours; a small irreversible one is not.

**Ask for exactly three things:** irreversible or outward-facing acts (`make
pin`, force push, deleting data, anything leaving this machine); genuine forks of
intent (Track U); authority only he holds (sudo, hardware, money).

**Everything else: act, then report.** Reporting is not asking.

**The worst question is one a MEASUREMENT would have answered.** Before
escalating, ask what you would have to measure for the question to disappear.

## The name is not the thing

**An identifier standing in for the thing it names, trusted because it looked
right.** An 80%-accurate name is worse than a 0%-accurate one — the part you
sample confirms it. A stale imperative can be **obeyed by tooling while false in
the world**.

**Every instrument that lies, lies by being CORRECT ABOUT SOMETHING ELSE.** A
stale binary, a stale tree, a store-local `cat-file`, a truncated `tail`, a
`grep -L` answering about a literal string. **None error. All answer.** So the
guard cannot be "check for errors".

**Do not ask "is it verified" — ask "what would this be if it were false", and go
look at THAT.** A comment: read a caller. A slug: open the ticket. Twelve hex
characters: `git merge-base --is-ancestor <sha> origin/master`, never
`git cat-file -e`, which answers about your own object store.

**A verification claim scopes to exactly what was checked**, and an unlabelled
claim travelling beside it inherits that credibility. Name the facts you checked,
or claim none.

**An EXCULPATION NEEDS AN OWNER FOR THE RESIDUAL QUESTION.** "Not X" is half a
finding — name who owns "then what?" before closing.

**A GUARD THAT CANNOT FAIL IS NOT A GUARD, AND IT PRINTS PASS.** Every guard
needs a **positive control**: a case it must reject, asserted. The same applies
to any "proof-grade" flag — a flag that cannot come out false is the same animal.
And a **gate that cannot pass** is not a gate either.

## Debugging — measure, do not reason

**The expensive bugs here do not crash; they produce a plausible wrong value far
from the cause.** A crash has a location and is the cheap case.

| question | tool |
| --- | --- |
| does it disagree with the oracle? | `tools/pydiff.py` (CPython), `tools/fpc_diff_probe.sh`, `tools/gcc_diff_probe.sh` (`--target` for cross); index in `devdocs/dev/differential-probes.md` |
| memory read after free? | `-dPXX_HEAP_DEBUG` — freed bytes become `$DD` |
| who retained/released it? | `-dPXX_OBJTRACE`, then `grep <addr>` |
| step through it | `-g -O2` + gdb, `source tools/pxx-gdb.py`, `pxxrc <obj>` |
| what did the COMPILER infer? | `PXXDBG=n.locals`, `n.ctorargs`, `a.ir:<proc>`, `a.ast:<proc>`; `make pxx-debug` (**forces `-O0`** — never quote its profile as `-O2`) |
| my change measured as NO CHANGE | data about your MODEL — playbook, "Reading a NEGATIVE result" |
| where is the time going? | not `perf` (dead here) — gdb SIGINT-sampling; min-of-N interleaved A/B, never means |

`PXXDBG` exists because editing a probe into the compiler and self-compiling
(~90s) is how a **wrong root cause got recorded**. Do not theorise about an
inferred type; print it. **Check every conclusion against a second source before
writing it into a ticket.**

**`devdocs/dev/debugging-playbook.md` has the tool for your case — LOOK UP THE
SECTION.** 279KB, ~70k tokens, 72 sections; `grep '^## '` lists them free.

## "You are the coordinator"

**Read `devdocs/dev/session-roster.md` — it is ~8KB and it is the whole job.**
(It was 1.53MB / ~384k tokens until 2026-08-31; the 322 dated log sections moved
to `session-roster-history.md`, which you `grep`, never read.)

**The coordinator does NOT distribute work** (owner, 2026-08-31). Dispatch is
cut. Its **sole** job is **topic-collision avoidance**: agents tell it what they
are working on; it speaks up **only** when two are on the same TOPIC — the one
conflict git cannot see. **Same FILE is not its business.**

It does not pick tickets, fill queues, treat an idle session as available, or
start a worker the owner has not started. **It sets up no timed callbacks** — it
is the session most tempted, because polling looks like coordinating.

**Relay stays, and is the valuable part** — workers cannot see each other. They
should also message each other directly; peer-to-peer beat routing every time.
**Sequence the few things that genuinely serialise:** `make pin`, and landing
order when a change is only correct as a whole. **Arbiter rarely**; route forks
to Track U. It holds no lane and writes no code.

## The per-fix loop — this file is the authority

**All tracks work on `master`.** No worktrees, no clones, no `dev` branch.
(Track T's watcher runs in its own clone; that is infra.) **Rebasing master is
wrong** — tstate verdicts and `resolve` citations are keyed by sha.

```
make compiler/pascal26     # ~12s — and it IS the byte-identical self-host fixedpoint
<run your repro / the one assertion you added>
git commit && git push     # tools/sync.sh does the pull --rebase + push
```

**`make compiler/pascal26` is mandatory and is not a test — it is the build.** A
compiler that cannot reproduce itself is the one failure that would poison every
lane, and this catches it in ~12s.

**Two scope limits on the fixedpoint — the SENTENCE is broader than the PROOF:**
1. It holds at the **default `-O` only**.
2. **It cannot see a construct the compiler never writes.** `compiler.pas` is a
   deliberately procedural subset — a duplicated `tkProperty` arm that spun
   forever passed cleanly, twice. **For C/N/R/Z it proves NOTHING about the
   frontend under edit. Track P's coverage is partial, which is worse than none
   because it looks total.**

Neither is an argument for a wider gate. **"My repro passed" is a different claim
from "the compiler still works"** whenever the repro is a construct the compiler
never writes — carry a one-line probe in the affected shape. For a MARSHALLING
change, carry one from **each frontend your quick tier does not cover**;
`x = "a" * 3` costs under a second and would have caught a shipped ABI mismatch.

**A CLEAN TREE IS NOT EVIDENCE ABOUT THE BINARY. The `converged after N round(s)`
line is.** `compiler/pascal26` is untracked, so `git status` says nothing about
which compiler is on disk. Three routes to a stale one: a seeded tree (`cp`
stamps a newer mtime, so `make` no-ops and exits 0), a reverted experiment, and a
sync that pulled someone else's `compiler/**`. **Rebuild after any sync touching
`compiler/**` before you measure, and print `sha256sum compiler/pascal26` beside
every number you report.**

**`make` has TWO success verbs and only one of them recomputed anything.**
`converged after N round(s)` (Makefile:284) is the recompute. `self-host
fixedpoint: verified — N round(s), <sha12>` (Makefile:317) is the STAMP path: it
asserts only that the binary on disk is still the one some past stamp was written
for, and its recipe never touches the binary. Seeing `verified` where you
expected `converged` means **no fixedpoint ran this time** — treat the binary as
unproven for your change, `rm` the stamp and re-run. Measured live 2026-08-31
(frankB): a pull brought someone's `compiler/**`, `make` printed `verified — 1
round(s)`, and `gate.sh quick` went RED against the stale binary; removing the
stamp and rebuilding was GREEN. **The verb is the tell** — both lines are green,
both name a round count, and `tools/selfhost_stamp_devtest.sh` asserts each.

A **nonzero** exit deserves the same suspicion: grep
the tree for the error string — if the source lacks it, the compiler that printed
it is not the one you think you are running. When seeding from outside, `touch`
the sources after the copy.

**GATE BEFORE YOU COMMIT, NOT AFTER.** `gate.sh quick`'s FPC seed canary only
runs while `compiler/**` has **UNCOMMITTED** changes; on a clean tree it prints
`SKIP` and you get no FPC coverage at all. PXX prescans headers and FPC is
single-pass, so a whole defect class — declaration order, a duplicate forward
across two `.inc` files — passes `make compiler/pascal26` AND `--tier quick`, and
the canary is the only thing that catches it (live case `a057789bc`).

**`tools/gate.sh quick` (~30s) is OPTIONAL per fix, REQUIRED before a pin.**
Background it and **grep the log for the verdict** — a backgrounded gate's
notification reports the WRAPPER, and said `exit code 0` over `gate: RED (exit 1)`
three times in one day. Check its own stale-binary diagnosis before believing a
RED; `git stash` produces exactly that condition.

**Do NOT widen this loop — the repo refuses.** `.claude/hooks/no-full-suite.sh`
denies `make test*`, `gate.sh full|limited`, `testmgr --tier full|limited`, and
shell loops over a `test/` glob. Track T escapes with `PXX_TRACK=T`; anything
else with `PXX_ALLOW_FULL_SUITE=1`, **autonomously, no permission needed** — it
is a SPEED guardrail, not a permission gate. Run it when you genuinely need it
and say in the commit why quick was not enough. **Not** because the change
"touched something shared" (that is the trap), not because a ticket's `Gate:`
line says so (superseded), not because an older doc says so.

**Breadth is Track T's job** and comes back as tstate reports and tickets
(`tools/twatch.py --follow`). T samples the tip every ~8 commits and bisects
backwards — a persistent regression is caught within ~8 commits. It does NOT
cover anything transient or masked. **Widening your own gate spends the machine
that produces the 8.** The one exception: **T is PROVEN down** (`twatch.py
--status` exit 1, or `trackt.py health` DOWN — `git fetch` first). Slow or stale
is not proven.

**Precedence: CLAUDE.md wins.** Handoffs, resolved tickets and `done/` write-ups
are historical records of what a past session ran — not instructions, not
maintained. Never widen your gate on their authority and **do not "fix" them**.
A live `devdocs/dev/*.md` that contradicts this section is the bug.

## Workflow norms

- **You may land non-green** — read, fix, commit, push, next. What you must NOT
  do is push something you know is broken and say nothing: **note it in the
  commit message**, the only warning anyone gets.
- **Push OFTEN — pushing is the default, not a milestone.** Unpushed work is work
  Track T cannot see. Never push another agent's in-flight work.
- **Park held work as a PATCH or a STASH. Never a file copy.** Unconditionally.
  A patch goes through a merge and can therefore CONFLICT; `cp` has no merge step
  to fail at, so a restored copy silently reverts everything that landed while it
  sat there — as a clean commit no track letter sees. **Guard the REVERT, not the
  edit**: `git checkout -- <file>` is the safe restore.
- **Every sha you QUOTE:** read it off `git log origin/master` AFTER the push, or
  from `tools/sync.sh`, which prints it. **The ghost rate is ~100% by
  construction** — this repo rebases nearly every sync, so a pre-push `log -1`
  reads a doomed id every time. Pass **no sha** to `resolve`; it writes
  `PENDING-COMMIT` and `sync.sh` fills it in. Recover a ghost by matching the
  commit **subject** on origin/master.
- **Tickets live in** `devdocs/progress/{urgent,working,unfinished,blocked,done,
  rejected}/` and, for open unclaimed work, **per-lane backlogs**:
  `backlog-core` (A), `-nilpy` (N), `-tools` (T), `-pascal` (P), `-decide` (U),
  `-libs` (B/E), `-cfront` (C), `-web` (W), `-windows` (M), `-docs` (D),
  `-esp` (S), `-umbrella`. All ranked identically; the win is that `ready --track
  N` reads one folder. Bugs vs features stay on the slug prefix. Regenerate
  `BOARD.md` after moving anything.
  **Auto-filed regressions carry `track: T` as a FALLBACK, not a finding** —
  re-lane before working, and do not guess the lane from the failing step.
- **`working/` is a status hint, not a lock; `owner:` is ATTRIBUTION, not a
  claim** — a parked ticket with an owner is free to take, message them for
  context. **Re-`claim` when you resume parked work.**
- **Self-serve queue:** `tools/progress.sh next --track <X>` names the entry
  point; `ready --track X` is the ranked queue. Then widen to the group. Loop:
  `pull --rebase` → `next` → claim → do → land green → `resolve` → `board-md` →
  `tools/sync.sh`.
- **Cold start ("continue on tickets"):** pull, `next`, **just take it** — there
  is no sole-A guard and no grant to request. If you know someone is mid-edit in
  the same *function*, message them; do not ask permission.
- **Agents read `devdocs/progress/BOARD-brief.md` (~6KB), not `BOARD.md`
  (344KB).** `tools/progress.sh ready|next` beats reading either.
