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
- **PINS ARE NOT RELEASES, AND STAYING IN SYNC WITH `lib/rtl` IS A PRIMARY
  PURPOSE OF PINNING** (owner, 2026-09-06): *"yes staying in sync with the rtl is
  a primary purpose of pinning. this is also why we have to pin on regular
  intervals, even if there are reds. pins are not releases."* **Pin on a regular
  cadence, reds included.** The pin and `lib/rtl` are ONE artefact and the pair
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
  **The cost of not pinning is not hypothetical: a fix is INERT UNTIL PINNED.**
  Two dated casualties in 48h — `IEnumerator<T>.Current` inert for a MONTH with
  its parser fix closed in `done/`, and `8374118ec` landing three hours after
  pin v404, which put a RED into every session's `gate.sh quick`, not merely
  into a sampled tier. **Before closing a compiler fix that a `lib/**` file
  depends on, check whether a pin carries it and say so in the resolution.**
- **A VALID PIN IS THE SELF-HOST FIXEDPOINT. NOTHING ELSE MAY BLOCK ONE** (owner,
  2026-09-01). Not a red tier, not a red count, not a shadow verdict. A pin is
  GRADED, never gated: `green` (a full tier at that tree, no RED) or
  `reds(N)` with the manifest, recorded AT PIN TIME. Rollback prefers a green
  pin and falls back to the most recent, so recovery is never empty.
  **A red is a reason to pin SOONER, not later** — the pin in place is red too,
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

**`devdocs/dev/debugging-playbook.md` has the tool for your case — LOOK UP THE
SECTION.** 905KB, ~225k tokens, 237 sections — it has TRIPLED since this line
first quoted 279KB/72, so treat any size in a pointer as a lower bound with a
date on it. `grep '^## '` lists the sections for a few thousand tokens, which is
cheap, not free.

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
`Co-Authored-By` does not, because every agent shares it. **Nothing in the COMMIT maps
an id to a session name**, and an id changes when a session restarts — but the
mapping is recoverable without asking, because each session commits in its own
checkout first: `git -C ~/<name> reflog --format='%h %gs' | grep '^<sha> commit'`
names the tree that CREATED it. Plain reflog membership does NOT discriminate —
every pull walks a sha through every checkout's HEAD — so match on the `commit`
entry, not on presence. Verified 2026-09-02: seven of eight shas in one arc,
one checkout, one id. **And it answers WHERE a commit was authored, not WHO
authored it** (frankD's caveat, the same day): a cherry-pick, a rebase that
re-creates commits, or one session applying another's patch all put the wrong
tree's reflog behind the sha. **The EIGHTH sha not resolving is the instrument
telling you it has a failure mode** — read that as the tell, not as noise.
Corroborate with the id before acting on a single sha. Do not fall back
to attributing by timing and topic: that produced the false alarm above, and it
produced a second one the same night, hours later, by this rule's own author.

**A CLEAN TREE IS NOT EVIDENCE ABOUT THE BINARY. The `converged after N round(s)`
line is.** `compiler/pascal26` is untracked, so `git status` says nothing about
which compiler is on disk. Four routes to a stale one: a seeded tree (`cp`
stamps a newer mtime, so `make` no-ops and exits 0), a reverted experiment, a
sync that pulled someone else's `compiler/**`, and — measured 2026-09-01,
`df1a8c17c` — **the positive-control discipline itself.** Proving a fix by
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
  not wait for it. `git commit` alone does not move the tree — only the pull
  does — so commit locally and push when it ends; the exposure is the sweep's
  length and there is no fully safe option, only a bounded one. A sweep reading
  a `git archive HEAD` snapshot instead of the tree would close it — untested,
  and it silently omits untracked files and the compiler binary.
  **And a corrupted measurement that happens to survive the question you ended
  up asking is indistinguishable from a clean one** — that census was salvaged
  only because the eventual claim was about the distribution and not the count.
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
  loop, which is not the same thing as deleting the directory.** Write scratch under it, or under the session scratchpad, and
  walk away. If cleanup genuinely matters, it belongs in a **committed script**
  with a `trap ... EXIT` — reviewed once, run as a unit — which is what
  `tools/*.sh` already do and why they never trip this. If you must delete
  interactively, **spell the path literally.**
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
