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

**WHAT EARNS A LINE HERE: RECURRENCE, NOT QUALITY.** Merit decides whether a
finding is BANKED — a ticket, the logbook, `debugging-playbook.md`. **A second
independent subsystem** decides whether it is promoted to the file every
session pays for at startup. Running those two together is how an excellent
playbook entry gets argued up on how good it is, and it is how this file grew
to 72KB the first time. Measured 2026-09-09: six rules landed here in one
evening on one seat's unwritten judgement, and two findings of comparable
quality were deliberately left in the playbook and the logbook by the same
test — a sharp sentence about guards, and a silent-negative class whose guard
half was already covered here. **Say the decision out loud to the author**: an
author reads "not promoted" as "not valued" unless told which test it met and
which it did not. And prefer STRENGTHENING an existing rule to adding a
neighbour — three of tonight's six were extensions, and an extension costs a
sentence where a new rule costs a paragraph.

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

**ON PAR WITH THE LANGUAGE, NOT WITH FPC** (owner, 2026-09-01): *"on-par is on
par with the language. not with weird edge cases where the programmer actually
made a presumed error."* So the ceiling is not "no compiling program can reach
it" — a program can reach it and still have no claim on us. **Ask what the
source MEANT, not what FPC returned.** Where an input is only produced by a
mistake — a value outside the type it is being tested against, a construct whose
two readings differ only when the program is already wrong — FPC's answer is
**not a specification and matching it is not a goal.** Diverging there is
`rejected/`, not compat. Compat is for a divergence on code someone MEANT to
write. Evidence that settles it is real source that wants the behaviour;
absent that, prefer the answer that leaves the mistake visible.

**"COMPATIBLE WITH FPC" MEANS THE VALUE, NOT THE INTERMEDIATE'S TYPE** (owner,
2026-09-02): *"if we keep nitpicking like this, we get nowhere ... the outcome is
just correct."* **DOUBLE IS THE NATIVE EVALUATION TYPE** — we do not compute in
`Single` at all unless softfloat forces it; `Single` is a STORAGE type. An
expression being typed or evaluated at double width is therefore **the
architecture, not a defect**, and no ticket may report it as one.

**The test, and it is the only one: store the result in its DECLARED type and
compare THAT.** Match there and we are compatible. Every divergence in the
intermediate — `SizeOf(expr)`, which overload an intermediate selects, the
expression's static type — is **implementation latitude**. Measured 2026-09-02
(`50117fa6e`): for `a, b: Single`, `s := a + b` gives FPC's exact bytes while
`SizeOf(a+b)` answers 8 against FPC's 4 and `P(a+b)` picks the `Double` overload.
**The first row is the claim; the other two are not.** Matching them would mean
rounding to single and widening — discarding precision we already have to
reproduce another compiler's rounding.

**NEITHER COMPILER IS WRONG HERE, AND `SizeOf` WAS NOT DIVERGING — IT WAS
WORKING** (owner, 2026-09-02): *"the programmer had all information it wants —
sizeof reported CORRECTLY about the accurate type. that's why it exists — to not
make assumptions."* `SizeOf(a+b)` = 8 is a TRUE statement about a pxx expression,
and FPC's 4 is a true statement about an FPC one. Each reports its own
compiler's representation, honestly, which is the entire reason the operator
exists. **A truthful instrument returning an answer you did not expect is not a
defect** — and a programmer who asks instead of assuming is served correctly by
both. This is a CLASS, not one ticket: where two implementations make different
but equally valid representational choices, introspection that reports each
choice faithfully is doing its job in both.

So these are recorded as **CHOSEN, never as tolerated**. "We accept this
divergence" invites a re-litigation because it concedes something was off; "both
answers are correct about different representations" does not.

Reopening one needs **real source, not a probe**, that is correct under FPC and
wrong under pxx *because of an intermediate's type*. A program that prints
`SizeOf` of an expression is not that — it is the operator working.

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
  **BUT A FIRST-FAILURE CENSUS RANKS BY QUEUE POSITION, AND A COUNT OF UNITS
  BLOCKED IS NOT A COUNT OF WORK.** The attempt reports the FIRST error per
  subject, so the walls behind it are invisible and a single call site in one
  shared dependency shows up as a huge number. Measured 2026-09-10, two
  umbrellas with no code in common and five null rows between them: on the FPC
  corpus, clearing the four largest walls in a row (158 units, 150, 96, 150)
  moved units-compiling by ZERO every time, and **three of those walls were
  the same FILE** — `cclasses.pas` at line 895 (`IndexQWord`), then 1327
  (`unaligned`), then 1726 (`Finalize`), each fix delivering its whole
  population to the next one a few hundred lines further down. The histogram
  was a picture of one file's contents; on lekkerzeilen, six import
  walls across two passes moved modules-compiling by zero, because imports sit
  at the top of a file and are structurally over-represented as first errors.
  **So do not rank a blocker on how many subjects name it**, and record the
  expectation BEFORE the re-run — a null row is only information to someone who
  said what they expected. The instrument that would answer the size question
  reports EVERY failure per subject, and on both umbrellas nobody had built it.
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
- **SUPERSEDED 2026-09-07 — "FULL GREEN EXPECTED" (owner): a pin RUNS a full
  tier and EXPECTS it green.** His words, set alongside cutting the fleet to two
  seats and naming Track P the priority: *"as far for pinning, let's get back to
  'full green expected'. so, we're no longer burning tokens fast, just back to
  slower workflow with hopefully less overhead."* **Read the two bullets below as
  the reasoning that produced the OLD rule, not as the rule.** They are measured
  and dated and they stay — what changed is the CALIBRATION, not the evidence.
  **What changes, and it is one thing:** the old rule let a pin go out on `quick
  GREEN, full tier NOT RUN` — v407 was pinned exactly that way on 2026-09-06 and
  that was correct then. It is not correct now. Run the full tier, expect green,
  **fix a red rather than grading past it.**
  **What does NOT change, and it is what will be re-litigated first: NEVER WAIT
  FOR A PIN.** That is the owner's own rule, said four times, and "full green
  expected" is not a licence to hold a seat until green arrives. An expectation
  that cannot be met **escalates to him**; it does not become an indefinite hold.
  If the full tier cannot run at all, say so and stop — do not pin blind, and do
  not sit.
  **The fixedpoint still gates; everything else still grades.** That distinction
  is untouched. "Full green expected" raises the bar on the rows that grade; it
  promotes none of them to a gate.
  **A SNAPSHOT ROW THAT A REVIEWED `--update` CLEARS IS PAPERWORK, NOT A RED.**
  Measured 2026-09-07: `tools/ast_slot_overloads.py` — wired into `gate.sh`,
  which is what arms before a pin — reds on any NEW AST slot write site, whether
  or not the site is legitimate, and `test/ast_slot_writes.expected` was touched
  **33 times, 20 of them in two days, five on 09-07 alone**, almost all Track P,
  which is now the priority. Its own failure message prescribes the remedy: check
  `ASTLeftIsChild`/`ASTRightIsChild` in `ast_arena.inc`, then re-run with
  `--update`. Review the diff, update, pin. Treating this class as blocking would
  stall a pin several times a day for bookkeeping — the stalled-worker failure
  mode wearing a green-looking justification.
  **The calibration, so a later reader knows what would make this stale:** the
  old rule was written for a fast fleet, where waiting cost 19 days with no pin
  (v354, 08-19, was the last green one). This one is written for **two seats and
  a slow cadence**, where the tree is usually green anyway and fewer sessions are
  standing on the result. **If the fleet goes wide again, revisit THIS bullet** —
  not the two below it.
- **PINS ARE NOT RELEASES, AND STAYING IN SYNC WITH `lib/rtl` IS A PRIMARY
  PURPOSE OF PINNING** (owner, 2026-09-06): *"yes staying in sync with the rtl is
  a primary purpose of pinning. this is also why we have to pin on regular
  intervals, even if there are reds. pins are not releases."* **Pin on a regular
  cadence, reds included.** (SUPERSEDED 2026-09-07 — full green expected.)
  The pin and `lib/rtl` are ONE artefact and the pair
  is only coherent within one era — each new builtin mints a cliff, roughly one
  a fortnight — so the way to have a coherent pair is to mint one OFTEN, not to
  make `make revert` cleverer. Measured 2026-09-05: usable rollback depth is
  ZERO; every historical pin is strictly worse against the current tree than the
  one in place. **Every instinct that says "do not pin while something is red" is
  RELEASE instinct** — the fear of shipping to someone who cannot roll back. A
  pin ships to this fleet's own inner loop and is replaced within hours. Applying
  release standards to it produces the outcome those standards exist to prevent:
  no pin at all, which is *"a worse outcome"* (owner, 2026-09-01).
  **WE AVOID ROLLBACKS — FORWARD IS THE RECOVERY PATH** (owner, 2026-09-06):
  *"yes we avoid rollbacks. useful work done is work done, even if (other)
  things break."* So a pin carrying a red is **a position the next pin
  improves**, never a liability to undo, and `pin_is_green`/`pinstatus` name a
  target for an operation this fleet does not perform — **do not rank a ticket
  on rollback depth and do not spend work making `make revert` produce a
  coherent pair.** The one thing still REVERTED rather than patched around is a
  change that breaks `compiler.pas`'s own fixedpoint; that is not a rollback,
  it is the single property a pin exists to carry.
  **AND NEVER WAIT FOR A PIN** (owner, 2026-09-06): *"sometimes we had a worker
  stop because it was waiting for a pin that never happened."* That is the THIRD
  failure mode of this rule and it is the one nobody wrote down — not
  under-pinning (49h with none) and not over-pinning (nearly blessing a bad
  fixedpoint), but **a session stalling itself on an event only the owner can
  cause.** A worker waiting on a pin is indistinguishable from a worker working,
  costs the whole session, and produces nothing to notice it by. **Land forward,
  say in the resolution what is inert until the next pin, and take the next
  ticket.** If your work genuinely cannot be verified until pinned, that is a
  sentence in the ticket, not a reason to hold the seat.
  **The cost of not pinning is not hypothetical: a fix is INERT UNTIL PINNED.**
  Two dated casualties in 48h — `IEnumerator<T>.Current` inert for a MONTH with
  its parser fix closed in `done/`, and `8374118ec` landing three hours after
  pin v404, which put a RED into every session's `gate.sh quick`, not merely
  into a sampled tier. **Before closing a compiler fix that a `lib/**` file
  depends on, check whether a pin carries it and say so in the resolution.**
- **A VALID PIN IS THE SELF-HOST FIXEDPOINT. NOTHING ELSE MAY BLOCK ONE** (owner,
  2026-09-01, and he has now said it at least four separate times — 09-01,
  09-06, and twice in the week before. **A rule its author has had to repeat four
  times is not being misunderstood, it is being re-litigated**, so treat a fresh
  argument for waiting as the thing this line exists to refuse, not as a new
  consideration). *"we NEED regular pinning, green or not"* (owner, 2026-09-06).
  **THE FIXEDPOINT ROW IS THE EXCEPTION THIS RULE ITSELF CREATES.** It is not a
  grade, because it IS the pin: **a row that restates the pin's own DEFINITION
  gates; every row that reports a property of the TREE grades.** Phrased as a
  reason and not as a row count, because a count goes stale the moment someone
  adds a row. Measured 2026-09-06: a seat authorised to pin, gating first as
  required, got RED on `self-host fixedpoint` and had to reason its way to
  stopping, because *"graded, never gated"* read as covering every red on the
  gate. Had it pinned, `test-smoke` would have chained from a local binary and
  blessed a fixedpoint the sources do not define — **both binaries self-reproduce
  and print green**, so nothing downstream could have seen it.
  Not a red tier, not a red count, not a shadow verdict. A pin is
  GRADED, never gated (SUPERSEDED 2026-09-07 for the TIER — a full tier is now
  run and expected green; the grading VOCABULARY below still stands and is what
  gets recorded): `green` (a full tier at that tree, no RED) or
  `reds(N)` with the manifest, recorded AT PIN TIME. Rollback prefers a green
  pin and falls back to the most recent, so recovery is never empty.
  **A red is a reason to pin SOONER, not later** (SUPERSEDED 2026-09-07: fix it,
  then pin — but do not WAIT on it either; escalate) — the pin in place is red
  too,
  and refusing on reds is an argument for never leaving a red pin. It held for
  19 days: v354 (08-19) was the last green one, while v398 shipped a compiler
  that could not build C for i386 or arm32 and every `$(PXX_STABLE)` consumer
  carried that for two days.
  **Read a shadow verdict as a GRADE, never as permission.** Three sessions
  reasoned carefully from `would_pin: false` and all three read a refusal —
  it is advisory, has zero deciding consumers, and `pin_shadow()` says it never
  touches `pinned` or `make pin`. A verdict nobody may act on gets read as
  authority anyway, so the fix is the wording, not the reader.
- **B / E — build with `$(PXX_STABLE)`, never rebuild the compiler.** A compiler
  or language gap → ticket in the owning lane.
  **VERIFYING A C FIX UNDER THE PIN CAN PASS FOR A REASON THAT HAS NOTHING TO DO
  WITH YOUR FIX.** Not a stale binary — the pinned compiler is *correctly* older,
  and the SOURCE branches on its age. Measured 2026-09-02: `busybox_diff.sh
  --pinned` shows PASS on the GNU-inline-asm ticket's own reproducer, because the
  pin predates `__GNUC__` (`00ab464bf`, not an ancestor of pin v399 `a7abc2481`;
  independently confirmed with an `#error` probe against the pinned binary), so
  `tls_sp_c32.c` takes its portable `#else` arm and never reaches the asm at all.
  **A green that is correct about a different compiler.** Any feature guarded by
  a version or feature-detection macro that landed after the pin has this shape.
  Reproduce at HEAD, and say which compiler a green was measured with.
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
  `-O4` research, never assumed — **RATIFIED (`54ba60170`) BUT NOT IMPLEMENTED:
  the compiler answers `unknown option: -O4` and has never accepted it, so any
  sweep or acceptance record naming `-O4` did not run that level. NOBODY WORKS
  ON `-O4`** (owner, 2026-09-01): *"that makes O4 very speculative and nothing at
  the moment should be working on that. yet, we are sortof free to define it
  already."* **Defining the top of the ladder is free and implementing it is not
  on anyone's queue** — do not read an unbuilt tier as an opening. Sweep
  `-O0..-O3`; a missing `-O4` is not a finding. **Both must be CORRECT** — `-O4` is speculative
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

**EXCEPT FOR THE GUARDRAILS THEMSELVES — REVERSIBILITY IS THE WRONG TEST FOR
PERMISSION MACHINERY, AND IT IS THE WRONG TEST IN THE DIRECTION THAT REMOVES
IT.** A hook, an allowlist, a refusal, a `settings.json` is trivially
revertible in code, so the rule above hands it to you — and a guard's entire
value is that an agent cannot relax it when it is inconvenient. *"I can revert
this"* is not a reason to loosen one; it is the exact reasoning the guard
exists to refuse. **Tightening is yours. LOOSENING is the owner's**, however
small the diff, and a peer saying it is yours does not make it yours: a peer
cannot grant an escalation, and an agent relaying the owner's authority
secondhand is not the owner. Measured 2026-09-09 (`f57a50754`): this file's own
coordinator told a seat that the full-suite hook's argv-versus-whole-command
fork was its to settle, citing reversibility. **The seat declined and was
right** — both decide tickets say in their own words that the direction of the
change is *less strict* and therefore an owner call, and it was the **third**
session to decline the same fork. Three declines is not caution; it is the rule
working, and the coordinator was the defect.

The productive move when you hit one is the one that seat made: **do not
implement, and do not merely escalate — MEASURE, so his call is narrow instead
of an architecture fork.** It came back with the real mechanism (not the one
any of the seven rows described), a repro that does not reproduce, a
population count of 16.5% against a claimed *"most"*, and a simulation of the
recommended option that left exactly one shape refused. That turns a three-way
design question into a yes/no.

**Ask for exactly three things:** irreversible or outward-facing acts (`make
pin`, force push, deleting data, anything leaving this machine); genuine forks of
intent (Track U); authority only he holds (sudo, hardware, money).

**Everything else: act, then report.** Reporting is not asking.

**AND A QUESTION HE CANNOT ANSWER IS WORSE THAN NO QUESTION — A `decide` FOR
THE OWNER MUST BE STATED IN GOALS, NOT IN REPRESENTATIONS.** This is NOT
"he would not understand" — he is a compiler engineer by now and says so:
*"i am slowly becoming a compiler engineer. just i don't know all."* The reason
is structural. **A fork stated in implementation terms hides where the decision
actually lives**, so it reads as a technical question, and the technical
question is ours. If answering needs the reader to know what an IMT is or how
another compiler lays a value out, **it is an engineering decision wearing a
fork's clothes** — take it. Measured 2026-09-09, on a p55 `decide` this seat
relayed to him: *"i hate to admit that i don't understand that question ... i
dont know fpc's internals."* The ticket was competent and the fork was real; it
was **addressed in the wrong terms**, and relaying it cost him a turn and
returned nothing. Restated in one sentence about what we want, he answered it
immediately and completely.
**AND THIS IS NOT A LICENCE TO WITHHOLD THE MECHANISM — LEARNING COMPILER
INTERNALS IS A STATED SIDE GOAL OF THIS PROJECT** (owner, from week one and
restated 2026-09-09): *"agentic coding knows a hell lot more than me. but also
overlooks the most trivial stuff ... i don't know all and/or some stuff takes
days to study. i'm not ashamed to not know all."* So the rule is about **what
he must ANSWER**, never about what he may READ. Put the decision in goal terms
so it is decidable; then explain the mechanism plainly beside it, because he
wants it. A seat that answers *"that's internal, don't worry about it"* has
obeyed the letter of this rule and defeated one of the project's own aims.
**And do not treat an "I don't know" as a problem to route around** — it is an
ordinary, precise report from a specialist about the edge of their
specialisation, offered so you will answer rather than assume. Answer it.

**The test before it goes up: can you state the fork as a sentence about what
we WANT, with no implementation noun in it?** *"Do we want pxx and FPC binaries
to exchange objects, or only for FPC's source to compile correctly under pxx?"*
is answerable by him in one word. *"Synthesised RTTI shim, or move to FPC's
interface representation?"* is not, and both sentences name the same fork. If
you cannot write the first sentence, you do not yet understand the fork well
enough to escalate it — and writing it usually reveals that **an existing rule
already decides it**, which is what happened here.

**Cost is not the fork.** Two options priced against each other is engineering.
It becomes his only where the options differ in what we are TRYING TO BE.

**HIS ANSWER, AND IT SETTLES A CLASS AND NOT ONE TICKET** (owner, 2026-09-09):
*"the challenge is just to compile FPC as a proof of pudding. we don't target
any advanced compatibility ... FPC is a great compiler and we have other goals,
the common thing is pascal and that we sayd we target FPC's dialect as de-facto
standard."* So **the dialect is the target and the implementation is not.**
Binary interop with FPC — exchanging objects, sharing a representation, linking
against its output — **is not a goal**, and no ticket may be ranked on it.
Compiling FPC is a PROOF, not a compatibility programme: a divergence found
while attempting it is a bug only if it stops correct Pascal compiling or
running, never because FPC does it differently.

**The worst question is one a MEASUREMENT would have answered.** Before
escalating, ask what you would have to measure for the question to disappear.

**BUT ASKING HIM FOR HISTORY IS CHEAP, AND IT IS THE ONE THING NO MEASUREMENT
REACHES.** Everything above is about asking him to DECIDE, which is expensive.
Asking him what HAPPENED — why a thing was built this way in July, what a
decision was reacting to, whether something was tried before — costs him one
line and is often unrecoverable otherwise. **He holds a continuous model of
this project across months; a session holds one context window and then loses
it.** His framing, 2026-09-09: *"you are like the 200IQ genious with a 3-second
goldfish memory ... i know stuff about 3+ month of development that you simply
dont unless you research it time and time again."* That is not modesty, it is
an accurate description of the memory architectures, and it has a cost: a seat
that reconstructs history from `git log` and ticket bodies spends real tokens
to produce a worse answer than one question would have. **Reconstruct the
record; ask him for the reasoning behind it.** And when he answers, WRITE IT
DOWN where the next session finds it — his own point cuts at us too: *"code i
wrote myself. 2 year later i'll have no clue unless i left notes."* Asking him
the same question twice is the version of this that is genuinely expensive.

## The name is not the thing

**An identifier standing in for the thing it names, trusted because it looked
right.** An 80%-accurate name is worse than a 0%-accurate one — the part you
sample confirms it. A stale imperative can be **obeyed by tooling while false in
the world**.

**AND THE MOST EXPENSIVE STALE ROW IS A HAZARD BLOCK, BECAUSE OBEYING ONE
PRODUCES NO SIGNAL.** A stale fact gets contradicted by the next measurement; a
stale WARNING is written to stop a reader, it succeeds, and a reader who stops
generates nothing that could reveal it was wrong. Measured 2026-09-09
(`e1808ad71`): the sized-boolean ticket carried an `ORDERING HAZARD` block
saying the feature would ship four more instances of a sibling bug. That bug was
closed and the fork it named was not merely decided but BUILT — and two further
rows of the same ticket were stale as well. It was found only because the seat
**re-measured instead of reading**, which is the one behaviour a hazard block is
designed to discourage. So a warning does not decay like a fact, it decays like a
LOCK: silently, in the direction of doing nothing, for as long as it is trusted.
**Re-measure the hazard before you obey it**, and when you write one, date it and
name the measurement that would retire it.

**Every instrument that lies, lies by being CORRECT ABOUT SOMETHING ELSE.** A
stale binary, a stale tree, a store-local `cat-file`, a truncated `tail`, a
`grep -L` answering about a literal string. **None error. All answer.** So the
guard cannot be "check for errors".

**DO NOT TOUCH THE INSTRUMENT WHILE IT IS MEASURING.** Two runs lost on
2026-09-02: a `git pull` mid-sweep left the binary snapshotted at one sha while
the harness read test sources from a tree that had moved, and — worse —
**editing a shell script that is currently RUNNING corrupts that run**, because
`/bin/sh` reads a script INCREMENTALLY, not into memory. That one returned
`rc=2` on three shards: a shell parse error wearing the shape of a verdict. The
tell is an rc that no test in the harness can produce. Land the edit, then start
a clean run from a tree equal to origin, and say which.

**Do not ask "is it verified" — ask "what would this be if it were false", and go
look at THAT.** A comment: read a caller. A slug: open the ticket. Twelve hex
characters: `git merge-base --is-ancestor <sha> origin/master`, never
`git cat-file -e`, which answers about your own object store.

**`git fetch` MOVES REFS AND NOT YOUR TREE — so a `find`, `grep` or `ls` right
after one reads a tree you have just convinced yourself is current.** It does not
error; it answers about your last pull. Measured twice in one session
(2026-09-02, this file's own author): a `find` for a ticket reported it in
`working/` when origin had had it in `done/` for three commits, and the claim
went to the agent who had just resolved it. **The observation is identical to a
real defect** — `bug-t-check-has-no-aperture-for-a-ticket-whose-body-records-its-own-completion`
produces the same "finished ticket still open", so the reading misroutes rather
than merely being wrong. **The discriminator is a `pull`, not anything about the
ticket.** Ref-level checks (`merge-base --is-ancestor`, `ls-tree origin/master`)
are correct after a fetch; anything reading a PATH is not.

**A verification claim scopes to exactly what was checked**, and an unlabelled
claim travelling beside it inherits that credibility. Name the facts you checked,
or claim none.

**HEDGE THE PREMISE, NOT JUST THE INFERENCE — a careful-sounding caveat on the
CONCLUSION makes an unmeasured NUMBER more credible, not less.** Measured
2026-09-02, this file's coordinator: a ticket claimed *"eight open tickets name
shortstring, several cross-target"* and added *"I have not established that any
share a cause, and it would be wrong to claim it from a grep."* The inference
was properly hedged and **the count was simply wrong** — `ls
devdocs/progress/*/` globs every folder, `done/` included, so seven of the eight
were closed and exactly one was open. The instrument did not error; it answered
a different question. The visible caution made the number read as the checked
part, and a peer spent a census establishing that the premise was false. **When
you hedge, name which half you are hedging** — and count open tickets by
FOLDER, never by a glob across all of them.

**AND THE CLAUSE TO GO MEASURE IS THE QUANTIFIER, NOT THE VERB BESIDE IT.**
Measured 2026-09-07, twice in one session by one seat, in one subject, and the
second one reached the rules file through this seat's own hand. *"No seed
escapes it, the pin included, EITHER WAY"* — the pinned binary run in place
resolves its own snapshot builtin. *"A wrong CWD is LOUD, not silent — there is
no silent second builtin to fall into"* — from any of the **twenty** sibling
checkouts on this box the lookup fires silently. **Both measurements were real
and in both the QUANTIFIER was the invention**: one location sampled, all
locations asserted, with the checked half lending its credibility to the
unchecked half. That is why it survives review — a reader who interrogates the
verb finds it sound. **When a sentence you are about to land contains "either
way", "anywhere else", "no X escapes", "always", "cannot", that clause is the
one to go measure**, and a conclusion handed to you already carrying one is not
a measurement you may build a rule on: **ask which population it was drawn
from before you quote it, especially when it arrives labelled as a finding.**

**"NOTHING OBSERVABLY DIFFERS" IS A CLAIM ABOUT ONE TARGET, AND IT IS HOW REAL
BUGS GET RANKED AS REFACTORS.** Measured 2026-09-02, twice in one hour by one
session: `refactor-a-the-const-cast-width-table-is-the-third-copy` was filed at
**prio 35** with *"not a bug today: nothing observably differs"* — and
`NativeInt`/`PtrInt` were 8 bytes unconditionally, so `const A =
NativeInt(2^32+5)` folded to 4294967301 on i386, arm32 and riscv32 while the
runtime cast of the same expression **in the same program** gave 5. A const
that does not fit its own type, no diagnostic, three targets.
`bug-a-method-pointer-record-is-hard-sized-16-bytes-on-32-bit-targets` was
**prio 20** and wrong on riscv32, which its own body had listed as *"same code
path, not run"*. **Both authors were honest and both measured on x86-64.**
The dev loop, `gate.sh quick` and the pin all run there, so a whole defect
class — anything whose width, alignment or pointer size is native-only — is
**structurally invisible to the instrument that would normally catch it**: the
pinned control on the method-pointer fix PASSES on x86-64 and fails two rows on
i386. A ticket saying "no observable difference" has usually established "no
difference **where I looked**", and where anyone looks by default is the 64-bit
host. **Before ranking one down, ask which target the absence was measured
on** — and prefer a test asserting RELATIONS (`SizeOf(P) = 2 * SizeOf(Pointer)`)
over per-target constants, so it carries no expected width and passes
everywhere while printing a different correct number on each.

**An EXCULPATION NEEDS AN OWNER FOR THE RESIDUAL QUESTION.** "Not X" is half a
finding — name who owns "then what?" before closing.

**A GUARD THAT CANNOT FAIL IS NOT A GUARD, AND IT PRINTS PASS.** Every guard
needs a **positive control**: a case it must reject, asserted, and **drawn from
the population your question is about** — a control from the wrong population
passes and certifies the broken instrument. The same applies
to any "proof-grade" flag — a flag that cannot come out false is the same animal.
And a **gate that cannot pass** is not a gate either.

**AND A CENSUS BUILT ON THE HYPOTHESIS IT IS TESTING WILL AGREE WITH IT.** The
guard rules above are about what an assertion can OBSERVE; this is about what
the SELECTION CRITERION already assumes, and it is the earlier failure — the
counterexample is filtered out before any assertion runs, so a correct
assertion over a question-begging population returns a clean, confident,
wrong number. Measured 2026-09-09 (`6aa50d6eb`): a ticket predicted that
widening a regex would make certain rows *"newly match"*, and the census
written to check it filtered on **newly matches** — the ticket's own premise —
so it reported 0 of 5987 lines affected and could not see the one row that
does move. The premise was false in a way the defect itself proves: those rows
already matched, and matching a suffix of the prefix is *precisely why* the
path was being mangled. **The fix is to compare OUTCOMES, not to filter on the
claim** — `OLD.sub()` against `NEW.sub()` per line, which found it. So before
trusting a count, ask **"what did I have to believe to decide what to count?"**
A census whose filter restates the hypothesis is not evidence for it, however
large N is, and N being large is what makes it persuasive.
**AND THE SAME MISTAKE IN AN ASSERTION IS BORN RED.** Measured the same day,
same seat, same subject (`6aa50d6eb`): a guard was written to pin a live
Makefile row, asserting the exact string *the ticket* said was there — and the
row had already been respelled by another seat, in a commit that is an ANCESTOR
of the guard's own. It could never have passed once. **An assertion written
from a REPORT of the code pins the report, not the code**, so it fails on
arrival and reads as a regression in whatever landed beside it. Both halves of
that collision were correct fixes; only the guard was wrong. Before pinning a
live line, `grep` for it in the tree you are committing to — not in the ticket
that describes it.

**AND A MEASUREMENT CAN CREATE THE CONDITION IT IS TESTING FOR — ITS OWN
EARLIER STEPS ARE INSIDE THE POPULATION.** The two rules above cover a control
drawn from the wrong population and a filter that restates the hypothesis. This
is the third and it is invisible to both, because here the population is right
and the filter is honest: **one PASSING part of the run supplies what a FAILING
part needs, so the failing part passes.** Measured twice on 2026-09-10, two
seats, unrelated subsystems. A fixture exercising a seven-member builtin family
passed while six of the seven were unreachable — the one member already wired
into the builtin auto-include scan dragged the unit in, and every unwired name
in the same file then resolved for free (`dbb96cdb6`). And a NilPy `import`
re-measured after a fix looked like it had begun resolving, to a scratch file
the same seat's OWN earlier probe step had left in that directory. Both were
correct behaviour and contaminated measurements, and in both the contaminant
was the measurer's previous step — which is why neither seat suspected it.
**A whole-family test is the exact shape that certifies the broken half.** The
general remedy is to ISOLATE the at-risk case from everything the run has
already produced — a fixture naming none of the working members, a probe in a
directory an earlier step did not write to — and let the asymmetry be the
control. The question that catches every form of it: **would this row still
pass if it were the ONLY thing in the run?**

**A positive control is not enough on its own — a guard must also be AIMED and
READ.** Assert that the thing under test actually RAN before you compare its
output (a comparison whose inputs were never proven to exist cannot fail), and
**branch on the assert — a precondition you do not branch on is a comment**
(`&&` between shell stages, not `;`). The two checks are INDEPENDENT: a `cmp`
harness with a must-differ row passes its positive control on every row that
compiled, and still reports `DIFFERS` for the rows where nothing was built.
Four instances in 24h, worked: debugging-playbook.md, "Assert the PRECONDITION,
not just the comparison".

**MATCH THE ASSERTION CLASS TO THE DEFECT CLASS — some bugs cannot fail a value
check, BY CONSTRUCTION.** A leak is the clean case: it does not corrupt, it just
never gives memory back, so every output assertion still passes. Measured
2026-09-02: with the open-array ownership fix reverted, the test printed
`OPENARRAYFRESH OK` while 1504 of 3000 arrays leaked — only
`tools/assert_no_leak.sh` saw it (`allocs=3000 frees=1496`, exit 1; with the fix,
`frees=2993`, exit 0). An `expect_same` row alone would have certified the leak
as correct, and `test_open_array_no_leak.pas` — a test NAMED for the leak — is
green a million iterations deep and was green throughout. **Ask what your
assertion is PHYSICALLY able to observe before trusting it**; a positive control
drawn from the right population still passes if the instrument reads the wrong
quantity.
**AND ORDER IS THE SECOND DOMAIN OF THIS, WHICH A LEAK EXAMPLE ALONE DOES NOT
SHOW** — a reader with an ordering bug does not see themselves in a memory
example. Measured 2026-09-10 (frankB, Track N): `PyParseLValueAST` read
`X = Y = v` as the nested right-associative `X = (Y = v)`, so every VALUE landed
correctly and the STORES happened backwards. `l[idx(1)] = m[idx(2)] = n[idx(3)]
= rhs(7)` logged `['rhs', 3, 2, 1]` against CPython's `['rhs', 1, 2, 3]` **while
printing identical values**, so no `expect_same` row could ever have failed —
the same structural blindness as the leak, with a correct answer instead of a
missing free. The instrument is a log of SIDE-EFFECT ORDER, which no value
comparison contains. Whenever a construct has more than one effect, ask whether
your assertion can see their SEQUENCE, not just their results.

**AND CHOOSE A PROBE WHOSE RIGHT ANSWER DIFFERS FROM THE DEFAULT — an expected
value that COLLIDES with the failure value is a guard that cannot fail, even
when the assertion class is right and the control is drawn from the right
population.** Measured 2026-09-02 (frankc-af, closing the C members of
`umbrella-sizeof-is-one-answer`): `sizeof(*s.fp)` for `int (*p)[4]` answered
**4**, and 4 is not the element size — it is `TypeStorageSize(tyUnknown)`,
i.e. *nothing was recorded*. **The `int` spelling cannot tell a correct answer
from a blank one**, because the unknown default equals `sizeof(int)`. Only
`double (*dp)[4]` answering 4 rather than 8 separated them, and the umbrella's
own example had asserted that row for a day while it was already stale. So the
question is not only "can this guard fail" but **"if the machinery did nothing
at all, would this row still pass?"** — wherever a type's default, a zero, a
`sizeof(int)` or a pointer width is also the expected value, the answer is yes.
Re-derive any size row expecting 4 or `sizeof(void*)` before trusting it.

**AND THE COLLISION CAN BE MANUFACTURED BY THE READOUT, WHICH THE QUESTION ABOVE
DOES NOT CATCH** — there the machinery did nothing; here it does plenty and the
INSTRUMENT collapses the two answers on the way out. Measured 2026-09-06
(frankB): `High`/`Low` of the sized booleans were recorded in a ticket's table
AND in a compiler comment as fpc answering `TRUE`/`FALSE`, agreeing with us.
Both readings came from `WriteLn`. Cast to `Int64` first and fpc actually gives
**9223372036854775807 / −9223372036854775808 for all four widths** — a value
that does not fit the type the expression has, which fpc's own assembler then
refuses. `Ord` and `WriteLn` truncate those extremes to the type's width, which
is **exactly the −1 and 0 we return**, so the probe reported parity on the one
row where the two compilers disagree completely. **It sat in a ticket for two
months, and an implementer matching the recorded table would have shipped the
wrong values believing they had parity.** The tell was visible without any cast:
fpc's `WriteLn(Low(ByteBool))` prints `TRUE` while fpc's own `Ord` of it is `0`
— **one compiler, two doors, two answers.** So ask the third question too:
**"could the way I am PRINTING this turn a disagreement into an agreement?"**
Any readout that formats, truncates, or narrows to the subject's own type can,
and a differential probe is where it costs the most. Widen the readout — cast to
the widest type, print the raw bits — before recording a row as parity. Record
the METHOD beside the number, never the number alone.

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
writing it into a ticket — but a second source only counts if it FAILS
DIFFERENTLY. Two readings that can go wrong the same way are one reading.**
Measured 2026-09-01: two sessions produced the same wrong count from the tstate
archive at the same time, from different causes (guessed keys sorting as `None`;
a job-name substring that swallowed all six shards), and the agreement read as
corroboration. The wide match also **synthesised a structural finding that did
not exist** — shards clearing in two groups reads exactly like one job flapping
— so **a "finding" that falls out of a grep needs the same interrogation as one
that falls out of a hypothesis.**

**A SPECULATIVE PARSE AND THE COMMITTED ONE CAN DISAGREE, AND THEN NEITHER THE
ERROR NOR THE ABSENCE OF ONE IS ABOUT THE TREE.** Measured 2026-09-09
(`ad7c03b03`), a bare method name in argument position: the overload probe
reached the reference door, built a correct `AN_METHODREF` **twice**, and
discarded both with the probe — *that* is what made the call MATCH — and then
the committed loop re-parsed the same argument as a CALL. **The verdict came
from one reading and the tree from another**, so by the time anyone looks, the
argument "is" a methodref, nothing is wrong with the match, and the only
suspect left is the layer below. The handed-over diagnosis duly blamed the
lowering and named a route that **had never run**. This is the house failure
mode in its nastiest position: the instrument is a successful overload
resolution, it is correct about the probe's reading, and it is silent about the
tree. **Where a construct is resolved speculatively and then re-parsed, dump the
AST — `PXXDBG=a.ast:<proc>` — before blaming anything below the parser.** A
door wired into the probe but not into the committed loop is a HALF-WIRED DOOR,
and it does not fail by refusing; it fails by agreeing and then building
something else.

**`devdocs/dev/debugging-playbook.md` has the tool for your case — LOOK UP THE
SECTION.** 1.27MB, ~317k tokens, 365 sections (measured 2026-09-07). It has more
than QUADRUPLED since this line first quoted 279KB/72 — and the 905KB/237 figure
that replaced it was written at `fe0c7e2cd` on 2026-09-06, itself a stale-rule
sweep, and was **stale within a day**: 910446 bytes / 240 sections there, 1268709
/ 365 one day later. So treat any size in a pointer as a lower bound with a date
on it, **including this one**. `grep '^## '` lists the sections for a few
thousand tokens, which is cheap, not free.

## "You are the coordinator"

**Read `devdocs/dev/session-roster.md` — it is ~8KB and it is the whole job.**
(It was 1.53MB / ~384k tokens until 2026-08-31; the 322 dated log sections moved
to `session-roster-history.md`, which you `grep`, never read.)

**The coordinator does NOT distribute work** (owner, 2026-08-31). Dispatch is
cut. Its **sole** job is **topic-collision avoidance**: agents tell it what they
are working on; it speaks up **only** when two are on the same TOPIC — the one
conflict git cannot see. **Same FILE is not its business.**

**A stated topic is the agent's BELIEF about its task, not its assignment** — a
citation sourced from a brief you have not read, arriving in the agent's own
voice. Check one that is unusually WIDE before acting on it, and never derive
advice from it. Measured 2026-09-01: *"auditing 470 tickets, all lanes"* was one
agent's brief written wrong, and guidance DERIVED from it told a worker to fix
frontmatter instead of fixing the ticket.

It does not pick tickets, fill queues, treat an idle session as available, or
start a worker the owner has not started. **It sets up no timed callbacks** — it
is the session most tempted, because polling looks like coordinating.

**HEALTH CHECKS ARE READ-ONLY. NEVER SEND KEYS INTO A PEER'S PANE.** Not Escape,
not "No", not a cancel — **not even the deny direction.** "Declining grants
nothing" is the reasoning that gets you there and it is wrong: you cannot tell a
pending dialog from running work, so the same keystroke either cancels one tool
call or **destroys a sweep in progress**, and the two look identical from
outside. If a session looks stuck, **ask it to CHECK ITS TRANSCRIPT** — not just
to report its state. Asking costs one message, but **a session cannot see its own
blockage**: measured 2026-09-02, frankA reported "not blocked, no prompt
pending" while a Bash call of its own sat rejected, because from inside a
session **a rejection and a denial-by-policy are the same string** — *"The user
doesn't want to proceed with this tool use."* A peer's self-report is its
BELIEF; its transcript is the record. Ask for the record.

**AND WHEN YOU READ THAT RECORD, READ *WHO* REFUSED.** "Is there a refusal in
your transcript" is not sufficient, because a **HOOK decline arrives as a
tool-result error and wears the same shape as a user denial.** Measured
2026-09-02: frankc-af, asked for the record, found exactly one refusal all
session — `.claude/hooks/no-full-suite.sh` declining a shell loop over a `test/`
glob — and it was **not a blockage at all**: it re-ran with
`PXX_ALLOW_FULL_SUITE=1`, which is a SPEED guardrail the agent lifts
autonomously, and said why in the commit. So the transcript has three things
that read alike — a user rejection, a denial-by-policy, and a guardrail the
agent may lift itself — and only the first two are a session being stuck.

**AND READ *WHEN*, BECAUSE A TRANSCRIPT GREP COUNTS YOUR OWN QUERY AND ANSWERS
ABOUT THE WHOLE SESSION.** Measured 2026-09-08 on this seat's own transcript:
`grep -c "The user doesn't want to proceed with this tool use"` said **16** where
the truth was **5**. The phrase is in the command text of every search for it and
in the output of every earlier one — **a grep for a denial cannot tell a denial
from a search for one, and the search is in the file by the time you read it.**
The discriminator is `is_error: true` on a `tool_result` block, never the string;
frankS reached the same place independently the same day and its own count was
inflated 4x. **And the AGE is the bigger trap: all five of mine were real and the
newest was SIX DAYS OLD**, in a session that had been working fine throughout —
so "is there a refusal in your transcript" answers YES for a seat that is not
stuck and never was. Ask whether the newest denial falls AFTER the last
successful tool call. Anything else is a question about the session's history
wearing the shape of a question about its state.

**AND "DID YOU SAY THIS?" IS A QUESTION ABOUT A RECORD, WHICH A SEAT WILL
ANSWER FROM A CONTEXT WINDOW.** Once the window has rolled, **NO is honest and
wrong at the same time**, and nothing in the exchange marks the difference —
the seat is not lying and has no way to notice. Measured 2026-09-09: this seat
flatly denied a claim a peer attributed to it, and the peer produced the
receipt with a timestamp. Grepping this session's OWN `.jsonl` found the
sentence **five times, role `assistant`, on 2026-09-08** — in the same file,
one command away, the whole time. The denial was made from memory because the
question *felt* like a memory question. **A seat's recollection of what it said
is not evidence about what it said; the transcript is.** **AND THE COUNT IS
THE PART THAT CLOSES THE ESCAPE: it was said FIVE times and still denied.** One
forgotten sentence is an ordinary memory failure and reads as carelessness;
five is proof that **the denial mechanism is not proportional to how firmly the
thing was said** — repetition does not survive a window roll, and having said
something five times makes it no more retrievable than having said it once. So
*"I would remember if I had really meant it"* is not available as a reason to
skip the check. Check
`~/.claude/projects/<proj>/*.jsonl` and filter on `role == "assistant"` before
denying authorship of anything older than the current window.

**A SCOPE WORD IS WHAT LETS BOTH SIDES BE RIGHT AND STAY WRONG.** The denial
above said *"every report I have sent him **this evening**"* — true, and the
quote was 29h50m old, so the two sentences never met. A qualifier like "this
evening", "in this window", "since I started" silently narrows a claim to the
speaker's visible horizon, which is exactly the horizon under dispute. **Name
the date, not the session-relative period.** The mirror half is the accuser's,
and the peer named it: *"the quote was accurate and the tense was not"* — a
29-hour-old statement was carried forward as a live intention. **A commit says
where a seat WAS and a message says what it BELIEVED; neither says what it is
doing now.** So quote with a timestamp, and check the tense before you stop
someone.

**"NO COMMITS IN N HOURS" HAS TWO CAUSES THAT LOOK IDENTICAL — blocked, and
ENDED ITS TURN.** Commit count cannot separate them and neither can the tree;
the discriminator is whether the session has an **unanswered turn**, which it
cannot see about itself either. Measured 2026-09-02: frankH, idle with no commit
for 5h45m, had no rejected call and nothing in flight — it had finished a ticket,
written *"Continuing down the queue"*, and ended the turn. **A session that
stopped short and a session that is stuck are the same silence.** Ask; the answer
is free and it is the only thing that separates them.

**A PANE IS NOT A SESSION, AND IT LEAVES NO RECEIPT.** `capture-pane` returns
committed scrollback plus the live screen; a Claude Code permission dialog is
drawn in the **redraw region and never commits**, so afterwards it is
unfalsifiable in both directions — a full-history grep finding nothing is not
evidence it was never there. Measured 2026-09-02: this session read a
`Dangerous rm ... $T/$n` dialog off frankA's pane, declared it "idle-blocked
since 01:10", and sent Escape; frankA was mid-sweep and reported no prompt
pending. **The peer's transcript is the only instrument that fails
differently** — it records a rejected call or an interrupt; the pane records
neither.

**A DISCARDED SHA READS EXACTLY LIKE A STALLED SESSION.** The whole false alarm
started by taking `361896c48` — a commit frankA had deliberately abandoned after
a peer landed the same root cause first — as "last activity". An agent that
resets to origin after losing a race leaves a local tip that is behind, recent,
and meaningless. **Never convert a sha's timestamp into a claim about a session**;
that question has an owner who can answer it for free.

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

**A CLEAN TREE IS NOT EVIDENCE ABOUT A SESSION EITHER.** "Clean tree at a sha
that is not the tip" is exactly what a session looks like the moment
`tools/sync.sh` returns — it is the SIGNATURE OF HAVING JUST LANDED, and it was
read as never having started. Measured 2026-09-01: frankH was judged idle on
it and had **eleven commits on origin/master that day**, the last eight minutes
earlier. The instrument answers "are there uncommitted edits" and gets read as
"has this session done anything". Ask the right question instead —
`git log origin/master --grep=<the session's Claude-Session URL>` — and note
the URL DOES discriminate (verified: two sessions, two ids), while
`Co-Authored-By` does not, because every agent shares it. **The id survives a
compaction and the git-status snapshot in your context does NOT** — that
snapshot names where this CONTEXT WINDOW opened, not where the session did, so
your own pre-compaction commits sit "before I started" and read as somebody
else's. Measured 2026-09-06: that reading produced a false *"the URL
over-matches"* finding about this very sentence, from two commits that were the
reader's own. **Nothing in the COMMIT maps
an id to a session name**, and an id changes when a session restarts — but the
mapping is recoverable without asking, because each session commits in its own
checkout first: **`tools/whose_commit.sh <sha>...`** names the tree that
CREATED it, across every checkout, with the session id beside it. Plain
reflog membership does NOT discriminate — every pull walks a sha through every
checkout's HEAD — so match on a **CREATING VERB**, not on presence. **`commit`
alone is not that set**, and this rule said it was until 2026-09-06.
`tools/sync.sh` rebases nearly every sync, and a replayed commit's `git commit`
sha is the DOOMED one — the surviving sha, the only one on origin and the only
one you ever quote, is born under a REBASE STEP. **And a rebase step run under
`git pull --rebase` is not spelled `rebase (...)` at all**: git prefixes the
step with the PULL's action, so the entry reads `pull --rebase -q (pick):
<subject>` and six such spellings are live in these checkouts. A bare
`pull ...` with no step suffix is membership and stays excluded.
**Do not write this verb set from memory — the reflogs enumerate themselves,
`git reflog --format=%gs | sed 's/:.*//' | sort -u` across every checkout, and
that one command beat two rounds of careful reasoning by two sessions on
2026-09-06.** Both of us listed the verbs we could think of and both lists were
short.
Measured 2026-09-06: 33 of one session's 69 commits answered a rebase verb, so
`grep '^<sha> commit'` denied **46% of its arc, the pin the fleet was running on
included** — it reported the tree that authored pin v405 as no tree at all.
**The old matcher was blind exactly when the fleet is busy enough to make
attribution worth asking about**, and it read cleanest on a quiet tree. Use
the script rather than retyping a regex: it holds the full creating-verb set
(`amend`, `fixup`, `squash`, `reword` too), and it exits **1** on both failure
shapes — no checkout claiming a sha, and two claiming it — instead of printing
a confident single name. The
membership noise it was guarding against is real and still separable: that
arrives as `rebase (start)`, `pull`, `reset`, `checkout` or `merge` — verbs that
MOVE a ref and never mint an object — and one such `rebase (start)` in a
BYSTANDER checkout is what a plain-presence match trips on. **The 2026-09-02
eighth sha, filed then as an unexplained tell, was a rebase and nothing more**;
the tell was real and pointed here. False positives for the corrected matcher in
60 non-matching commits: one, and it was this checkout's own `sync.sh`
PENDING-COMMIT fill-in — authored here, trailerless, so the reflog had it RIGHT
and the URL could not see it. **The two instruments fail differently, which is
the entire reason to hold both.** **And it answers WHERE a commit was authored,
not WHO
authored it** (frankD's caveat, 2026-09-02): a cherry-pick, a rebase that
re-creates ANOTHER session's commits, or one session applying another's patch
all put the wrong tree's reflog behind the sha.
Corroborate with the id before acting on a single sha. Do not fall back
to attributing by timing and topic: that produced the false alarm above, and it
produced a second one the same night, hours later, by this rule's own author.

**A CLEAN TREE IS NOT EVIDENCE ABOUT THE BINARY. The `converged after N round(s)`
line is.** `compiler/pascal26` is untracked, so `git status` says nothing about
which compiler is on disk. Five routes to a stale one: a seeded tree (`cp`
stamps a newer mtime, so `make` no-ops and exits 0), a reverted experiment, a
sync that pulled someone else's `compiler/**`, **`make bootstrap`** — it ends in
`mv $(BUILD_COMPILER) $(COMPILER)`, so it REPLACES your binary, and it is the
only route where the replacement is *legitimate*, so nothing looks wrong
afterwards; record the sha first and reseed from the pin after. **And if what
you are checking is the RELEASE property, do not run the target at all** — an
fpc-seeded binary byte-identical to the pin-derived one is release-blocking
evidence, and `make bootstrap` leaves your checkout on the very chain you were
testing against, so the check destroys the thing it was checking. Run the
recipe's lines into a scratch dir and omit the `mv`: measured 2026-09-07
(`0540e3f9d`), `PXXFLAGS` is empty and `FPCFLAGS` is exactly `-O2 -Tlinux
-Px86_64`, so that IS bootstrap's chain, and the only other thing skipped is
`bootstrap-check`, a `which fpc` guard. **Run every build and every bootstrap
measurement with the CWD at the REPO ROOT** — a `$(PXX_TMP)`-located binary
finds no builtin beside itself (`--where` prints `[MISSING]` for every exe-dir
path) and falls through to the **CWD-relative** last resort, which is how every
bootstrap stage links the LIVE `compiler/builtin/`.
  **THREE OUTCOMES, AND THE MIDDLE ONE IS THE WHOLE POINT:** no `compiler/`
  under the CWD → **loud** failure (`uses: unit source not found: builtinheap`,
  rc=1); **a SIBLING CHECKOUT → SILENT SUBSTITUTION**, the lookup fires and
  compiles THAT tree's builtin units into your binary; the repo root → correct.
  `ls -d /home/neo/*/compiler/builtin` answers **twenty** on this box, so the
  silent arm is the COMMON one. **This paragraph asserted "the wrong CWD is
  LOUD" for one hour on 2026-09-07 and that was a control drawn from the wrong
  population** — a scratch dir, which has no `compiler/` and therefore cannot
  fail any other way. **A byte-comparison does not catch the silent arm** while
  the two trees' builtins happen to agree, which is exactly until someone
  changes a builtin: measured, a build from a sibling root came out
  BYTE-IDENTICAL because the two `builtinheap.pas` differed only by a named
  constant versus its literal, and that reads as "CWD does not matter". Do not
  put a `builtin/` beside the staged binaries to make an error go away; that
  resolves against a copy and stops measuring bootstrap's chain.
  — and — measured
2026-09-01, `df1a8c17c` — **the positive-control discipline itself.** Proving a fix by
reverting it is revert→rebuild→restore→rebuild, and EACH REBUILD SEEDS FROM THE
PREVIOUS LOCAL BINARY; after a few cycles, with other agents' `compiler/**` and
**`lib/rtl/**` (also a compiler build input, which is the part nobody expects)**
arriving by rebase, the local seed walks off the pin-derived chain. `gate.sh
quick` then goes RED with *"the fixedpoint reached from PINNED differs from
`compiler/pascal26`"* — **two valid fixedpoints, not a miscompile**: both
binaries self-reproduce. **That RED is not a reason to distrust the fix.**
Recover by reseeding from the pin AND `touch`ing the sources. **Rebuild after any sync touching
`compiler/**` before you measure, and print `sha256sum compiler/pascal26` beside
every number you report — and the COMMIT beside the sha.** A sha names the
binary; it is not a source identity. `compiler/.pascal26.fixedpoint` holds
exactly `rounds N` and `sha256 <hex>`, so `verified` can tell you *which* binary
and never *what built it*; the `make pin` commit line (the `chore(stable): pin
vN` echo) carries the same sha-without-commit. `git diff HEAD -- compiler/ lib/` is not the
control it looks like: it proves the tree matches HEAD while saying nothing
about where HEAD is, and **107 commits touched `compiler/` or `lib/` on
2026-08-31, 11 in one hour.** Two agents on different commits legitimately hold
different binaries that both print `verified` — that is determinism, not
nondeterminism, and it was reported as a bug once (`9d867ee4d`).

**`make` has TWO success verbs and only one of them recomputed anything.**
`converged after N round(s)` (the `$(COMPILER_STAMP)` recipe) is the recompute.
`self-host fixedpoint: verified — N round(s), <sha12>` (the `$(COMPILER)`
recipe) is the STAMP path: its recipe never touches the binary. Since
`01dd27dd1` it also refuses outright when the stamp was written for DIFFERENT
SOURCES than the tree has, so it can no longer print success for a tree it
never saw — but it still does not mean anything was BUILT. Seeing `verified`
where you expected `converged` means **no fixedpoint ran this time** — treat the
binary as unproven for your change, `rm` the stamp and re-run. Measured live 2026-08-31
(frankB): a pull brought someone's `compiler/**`, `make` printed `verified — 1
round(s)`, and `gate.sh quick` went RED against the stale binary; removing the
stamp and rebuilding was GREEN. **The verb is the tell** — both lines are green,
both name a round count, and `tools/selfhost_stamp_devtest.sh` asserts each.
Those two citations name recipes rather than lines (since `b5a3f68bf`)
because the three `Makefile:<n>` they replaced had gone stale: all were correct when written
(`9a0f3bad9`, the same morning) and the `make pin` one had drifted **142 lines
by that evening** — to `fi; \`, a real line that explains nothing. A stale line
number does not error; it points somewhere.

A **nonzero** exit deserves the same suspicion: grep
the tree for the error string — if the source lacks it, the compiler that printed
it is not the one you think you are running. When seeding from outside, `touch`
the sources after the copy.

**GATE BEFORE OR AFTER THE COMMIT — the canary no longer cares, and this rule
used to say it did.** PXX prescans headers and FPC is single-pass, so a whole
defect class — declaration order, a duplicate forward across two `.inc` files —
passes `make compiler/pascal26` AND `--tier quick`, and `gate.sh quick`'s FPC
seed canary is the only thing that catches it (live case `a057789bc`). It arms
against the **MERGE-BASE**, so committed-but-unpushed is covered, and it arms a
second way when origin/master's `compiler/` has moved past the last sha THIS
CLONE proved. **The old rule here — "the canary only fires on an UNCOMMITTED
tree" — was true when written and is now false**; `tools/gate.sh` says so in its
own comment, calling it *"a footgun worth not copying"*. It was obeyed literally
by at least two sessions after it went stale. What still holds: a clean tree is
not a reason to skip the gate, and FPC being absent is a SKIP, never a pass.

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
that produces the 8.** The one exception: **T is PROVEN down** — and the
proof is **`twatch.py --status` exiting 1** after a `git fetch`. It is **NOT**
`trackt.py health`, which asks whether a watcher daemon runs on the **LOCAL**
host: **T runs on seven, and plexus deliberately does not run it** (owner,
2026-09-01), so on plexus it answers `DOWN — no watcher daemon is running` every
single time, correctly, about the wrong machine. Measured 2026-09-01: `health`
said DOWN on plexus while `trackt-watcher.service` was `active` on seven with a
fresh archive — and read literally, that would have handed every lane a
permanent licence to widen its gate. Slow or stale is not proven either.

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
  **A LOCAL COMMIT IS NOT BANKING.** A session is restarted without warning and
  the restart takes the commit with it. Measured 2026-09-02: of four sessions
  cycled for a Claude update, three held stranded local state — and frankZ's was
  `263ceaed3`, *"bank the 00213 diagnosis where a restart cannot take it"*, 257
  lines across five tickets, committed for exactly that reason and never pushed.
  The tree survives on disk, but the NEXT session has no idea it is there and is
  told by this file to distrust a diff it cannot explain. Push, or it is a diff
  nobody dares touch.
  **PUSH BEFORE A MEASUREMENT STARTS, NEVER DURING ONE — this is where "push
  often" and "do not touch the instrument while it is measuring" collide, and
  the answer is ORDERING, not precedence.** `tools/sync.sh` pulls before it
  pushes, so a sync during a sweep moves the population under your own harness.
  Measured 2026-09-06: two syncs during a 2276-file census changed 4 files
  mid-sweep. **Banking your work does not FEEL like touching the instrument, and
  it is** — which is why nobody scanning for instrument hazards looks under
  "push often". The collision window only exists if you start a measurement with
  work already unpushed. **The sequence is PUSH -> LET THE PULL SETTLE ->
  REBUILD -> MEASURE, and the REBUILD is the step that gets dropped**, because
  a push IS a pull: `sync.sh` banks your work by moving your tree, so the sync
  that makes you safe is itself the instrument-mover for whatever you measure
  next. Measured 2026-09-06, AFTER this very clause landed at `fe0c7e2cd` and
  43 minutes before pin v405: a seat followed the ordering, pushed, gated
  without rebuilding, and got `self-host fixedpoint` RED — four commits touching
  `compiler/**` had arrived in the pull, so `compiler/pascal26` was built from
  the old sources while the pinned-seeded chain compiled the new ones. **Two
  valid fixedpoints, not a miscompile.** The rule was present, correct, and
  inline in a paragraph about something else; that is why the sequence is on its
  own line now. **The red it produces is CORRECT AND MEANS NOTHING**, it is
  indistinguishable at a glance from the serious version, and it arrives right
  after a successful landing — when the tree feels settled precisely because you
  just settled it. **Residual, for a sweep of hours:** a restart does
  not wait for it — so the pull is not the only hazard. **`git commit` MOVES THE
  TREE for anything comparing the live tree against a pre-run stamp, and this
  rule said the opposite until 2026-09-07.** It does not change a file's
  CONTENT, which is why it feels safe and why the wrong version survived here for
  days; it changes the tree's IDENTITY, and `testmgr` reads that. Measured twice
  in one day, both seats following this line in good faith. frankS's native tier
  printed `WARNING the source tree MOVED during this run (c23e8d1e4253+7926ccfb
  -> c4ff2882da99+e3b0c442)` with its own gloss: *"a mid-run rebuild is harmless
  — the binary is snapshotted — but a pull or commit is not."* The warning only
  bites a RED, so a green run survives it and a red one is unattributable.
  **The certain shape is to start the tier from an already-clean tree.** Staging
  and holding (`git add`, no commit) is frankS's proposal and looks right, since
  staging does not move the commit — but it is NOT measured, so do not quote it
  as safe. The exposure is the sweep's
  length and there is no fully safe option, only a bounded one. A sweep reading
  a `git archive HEAD` snapshot instead of the tree would close it — untested,
  and it silently omits untracked files and the compiler binary.
  **And a corrupted measurement that happens to survive the question you ended
  up asking is indistinguishable from a clean one** — that census was salvaged
  only because the eventual claim was about the distribution and not the count.
  **AND THE OTHER DIRECTION IS UNGUARDED: A PULL CAN IMPROVE YOUR NUMBERS, AND
  THE IMPROVEMENT LOOKS EXACTLY LIKE YOUR OWN WORK.** Everything above guards the
  stale direction, where you claim a green you did not earn. This is the mirror
  and nothing was watching it: measured 2026-09-08, frankS's conformance run came
  back **418 pass / 47 gap** against its previous 417 / 48, a row burning in the
  same run as its change and in the same subsystem — and the row was another
  seat's, arrived in the pull it did three hours earlier. **A stale tree makes
  you claim a green you did not earn; a fresh pull makes you claim a DELTA you
  did not cause**, and a single number over a corpus every seat is burning at
  once cannot tell them apart. The discriminator is one command —
  `git log -S'<the row>' -- <the skip or expected file>` — and the reason it does
  not get run is the whole finding: **the number moved in the direction you
  wanted, which is the direction nobody checks.** Attribute a delta before you
  quote it, and say in the resolution which rows are NOT yours.
  **AND THE UNFAVOURABLE DIRECTION IS UNCHECKED TOO, FOR THE OPPOSITE REASON —
  YOU STOP LOOKING BECAUSE YOU HAVE FOUND A CULPRIT, AND IT IS YOU.** Read
  literally, the lines above say the unwatched direction is the flattering one.
  That is half true and the other half is nastier. Measured 2026-09-09 (frankB,
  `b59a53a99`): a tier row went GREEN in the first run and RED in the second
  with only its own change in between, and the red was exactly the failure that
  change could cause. It parked the patch and reverted — and the row was
  another seat's, arrived in the PULL between the two runs. **The suspect is
  your own diff and the evidence reads like a confession**, so the self-blaming
  reading TERMINATES the search, where a self-crediting one at least leaves a
  number someone may query. Same discriminator either way: **attribute a tier
  delta to a RANGE before attributing it to yourself**, and a pinned-versus-HEAD
  control settles it in one command.
- **Park held work as a PATCH or a STASH. Never a file copy.** Unconditionally.
  A patch goes through a merge and can therefore CONFLICT; `cp` has no merge step
  to fail at, so a restored copy silently reverts everything that landed while it
  sat there — as a clean commit no track letter sees. **Guard the REVERT, not the
  edit**: `git checkout HEAD -- <file>` is the safe restore. **NOT
  `git checkout -- <file>`**, which restores from the INDEX — so after anything
  that staged content (a `claim`, a partial `add`, a sha-form checkout) it
  faithfully re-applies the very state you are trying to back out of, and
  reports nothing.
- **NEVER issue `rm` as a Bash tool call with a VARIABLE or a GLOB in the path.**
  `rm -rf "$T/$n"`, `rm -rf $WORK/*` — these trip Claude Code's built-in
  dangerous-`rm` prompt, and **that prompt STALLS YOUR SESSION until the owner
  personally clears it.** Measured 2026-09-04: **frankA and frankB were both
  sitting on one**, frankA for **19 hours**. The owner had already asked once
  ("can you stop doing rm with environment vars please") and it kept happening,
  which is why it is a rule now and not a preference.
  **The cost is not the keystroke — it is that a blocked session and a working
  session look IDENTICAL from outside**, so the stall is only found when somebody
  asks. See "A PANE IS NOT A SESSION".
  **The fix is not to rephrase the command so it slips past the guard.** Do not
  do that, and do not ask a peer or the owner to run it for you — a guard you
  route around is a guard the owner no longer has.
  **You almost never need the `rm` at all.** `mktemp -d` already yields a
  disposable directory the OS reaps; **leaving it is nearly always right and
  deleting it interactively buys nothing.** Nearly: /tmp is a real 94G
  filesystem, not a tmpfs, and on 2026-09-06 it hit 99% — 48% of the volume was
  ONE orphaned session scratchpad, 159,442 files from an A/B loop that wrote a
  binary and a `.map` per iteration. The reaper was set to 10 days and the box
  filled in two, so it never got a turn. It is 6h now
  (`/etc/tmpfiles.d/tmp.conf`), which is what makes walking away safe — **a loop
  writing per-iteration artefacts should still clean up after ITSELF, inside the
  loop, which is not the same thing as deleting the directory.**
  **AND THE RESOURCE THAT RUNS OUT IS NOT ALWAYS THE ONE YOU MEASURE — SEVEN
  DIED ON INODES AT 9% FULL.** Measured 2026-09-07; it took the breadth
  instrument down for ten hours. `df -h /tmp` said 4.1G of 47G used, **9%**,
  while `df -i` said **8 free inodes of 1,048,576, 100%**. seven's `/tmp` IS a
  tmpfs, so the 94G sentence above is about PLEXUS and does not travel. testmgr
  builds its scratch there, every `mkdir`/`open(O_CREAT)` returned ENOSPC, and
  the tier died before running a single job — ~290 commits of `infra ... no
  report (rc=1)` at ~28/hour, each one testing the previous one's commit. The
  producer was ~40 families of temp dirs that devtests and twatch helpers never
  remove (`tstate-at.*` alone: 163,491 inodes in 241 directories over ~31 hours,
  `twatch.py:7613` calling `tempfile.mkdtemp` when the caller passes no `dst`) —
  no single runaway, which is why it arrives as a CLIFF and not a slope.
  **A disk guard that reads only bytes is a guard that CANNOT FAIL for this
  outage:** `shutil.disk_usage` and `f_bavail` both read healthy at the moment
  of failure. Record `f_favail` beside `f_bavail`, or the check reports a green
  box during the exact event it was added for. **Ask which resource is binding
  on THAT host before quoting a percentage** — and cleaning up per-iteration
  inside the loop matters more on a tmpfs, where the reaper's window and the
  inode ceiling are two different limits. Write scratch under it, or under the session scratchpad, and
  walk away. If cleanup genuinely matters, it belongs in a **committed script**
  with a `trap ... EXIT` — reviewed once, run as a unit — which is what
  `tools/*.sh` already do and why they never trip this. If you must delete
  interactively, **spell the path literally.**
  **THIS IS A HOOK NOW, NOT A NOTE** — `.claude/hooks/no-variable-rm.sh`,
  registered beside `no-full-suite.sh`, refuses an interactive `rm` whose target
  carries a `$variable` or a glob. Added 2026-09-07 because the owner reported
  it was **still** happening, after this rule was written and after he had
  already asked in his own words. Measured the same hour: **~170 such calls
  across ten sessions in four days**, the most recent 51 minutes before he
  said so. **There is no env escape and that is deliberate** — the way through
  is to spell the path, which is this rule's own instruction and cannot be
  abused. It denies INSTANTLY rather than stalling, which is the whole point:
  the built-in prompt costs hours, a refusal costs a retry. `tools/*.sh` are
  unaffected — the hook sees `tools/foo.sh`, not the `rm` inside it.
- **Every sha you QUOTE:** read it off `git log origin/master` AFTER the push, or
  from `tools/sync.sh`, which prints it. **The ghost rate is ~100% by
  construction** — this repo rebases nearly every sync, so a pre-push `log -1`
  reads a doomed id every time. Pass **no sha** to `resolve`; it writes
  `PENDING-COMMIT` and `sync.sh` fills it in. Recover a ghost by matching the
  commit **subject** on origin/master.
- **Tickets live in** `devdocs/progress/{urgent,working,unfinished,blocked,done,
  rejected,low-prio,known-incompat}/` and, for open unclaimed work, **per-lane
  backlogs**:
  `backlog-core` (A), `-nilpy` (N), `-tools` (T), `-pascal` (P), `-decide` (U),
  `-libs` (B/E), `-cfront` (C), `-web` (W), `-windows` (M), `-docs` (D),
  `-esp` (S), `-umbrella`. All ranked identically; the win is that `ready --track
  N` reads one folder. Bugs vs features stay on the slug prefix. Regenerate
  `BOARD.md` after moving anything.
  **Four terminal folders, and they say DIFFERENT things** — putting a ticket in
  the wrong one is how it gets refiled. `rejected/`: the report is **WRONG**
  (unreachable observable, false premise, not a goal). `known-incompat/`: the
  measurement is **TRUE and reproducible** and still not a defect — both
  behaviours are correct about their own implementation and ours is **chosen**,
  never merely tolerated. `low-prio/`: real, probably correct, and not worth
  ranker attention — no plan to do it, no claim it is wrong. `rainy-day/`: real,
  intended, **deferred** — a future plan. All are loaded (so citations resolve
  and `check` sees them) and none are ranked.
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
