---
slug: umbrella-pxx-compiles-fpc-itself
track: P
prio: 85
type: umbrella
status: backlog
owner: ""
created: 2026-09-09
found-by: frankuser
tags: [pascal, corpus, real-world, fpc, application-driven]
blocked-by: [bug-p-an-array-constant-with-a-set-element-type-cannot-be-initialised, feature-p-legacy-value-object-types, bug-p-a-conditional-directive-cannot-read-a-const-whose-value-is-not-an-integer-literal, bug-p-a-conditional-directive-cannot-evaluate-in-over-a-set-constant, feature-p-unaligned-is-a-transparent-lvalue-not-a-function, bug-p-a-semantic-diagnostic-in-a-used-unit-names-no-file-at-all, bug-p-a-method-parameter-typed-through-a-forward-pointer-alias-never-matches-its-own-body, feature-p-the-element-count-form-of-initialize-and-finalize, bug-p-a-set-valued-record-field-cannot-be-written-in-a-record-constant, feature-b-sysutils-has-no-executeprocess-and-no-texecuteflags, feature-b-rtl-has-no-tdoublerec, feature-b-rtl-has-no-termio-unit-and-no-isatty]
summary: "MEASURED 2026-09-16 WITH PXX_CORPUS_DETAIL, AND IT ANSWERS THE SIZE QUESTION THIS UMBRELLA ASKED FOR SIX NULL ROWS: 132 of 207 units report EXACTLY TWO errors and nothing else -- `unknown type: TDoubleRec` (x86_64/cpuinfo.pas:36) and `too many array initializer elements` (:281) -- BOTH IN ONE FILE, with the 20-error recovery cap not in play (one unit in the whole corpus reaches it). So the 132 are not merely QUEUED behind TDoubleRec; those two are their COMPLETE reported failure set. The second wall had no ticket and now does: bug-p-an-array-constant-with-a-set-element-type-cannot-be-initialised, the UNFIXED SIBLING of the record-constant arm that 138604b5e fixed. THE SIXTH NULL ROW IS CONFIRMED AND WAS PREDICTED BEFORE THE RUN: TDoubleRec ALONE delivers ZERO units -- 0 of the 132 have it as their only error. Expect a third wall in the same file rather than 132 units; what is new is that this is the first proposal with a complete failure set behind it instead of a queue position. Totals at 9281da35b: 21 BOTH-OK, 10 ORACLE-NO, 176 PXX-FAIL. Owner-set direction 2026-09-09: 'we are going to be more application driven, not just hunting down theoretical bugs but just.. let's get stuff rolling. so, we had practical targets like busybox. or compiling FPC itself.' NO TICKET FOR THIS EXISTED ANYWHERE IN devdocs/progress -- measured, zero hits. FPC's own compiler is ~400k lines of Object Pascal written by people who were not testing us, which makes it the largest and least self-serving Pascal corpus available, and it is the application-driven form of exactly what Track P has been doing by hand: every bug the P seats hunted from the backlog tonight would have been found by this target, in the order that actually matters. BLOCKED-BY IS GROWN BY ATTEMPTING, NEVER BY TRIAGE -- CLAUDE.md: 'Each failure names a ticket in the order it actually matters. What the attempt never touches was not blocking real-world usage.' STATE at 4c7c88d36 (attempt 7, probe #12): 20 of 207 units compile under both fpc and pxx, 10 are ORACLE-NO and can never be evidence about us, 177 fail. THE FOUR CONSECUTIVE NULL ROWS ENDED AND THEY ENDED CHEAPLY: cclasses.pas compiles, and the per-unit join says the +3 is exactly that unit plus its two direct dependents (crefs, rabase) -- so clearing the wall 150 units were stacked on was worth THREE, which is this umbrella's own queue-position finding confirmed rather than refuted. It took two bugs, both found by converting one halting diagnostic to ErrorRecover so a unit reports EVERY failure instead of the first: a method parameter typed through a forward pointer alias never matching its own body (ee560d0ad), and the element-count form of Initialize/Finalize (d095cb08d), which had been a DELIBERATE refusal. SEVEN walls cleared now; BOTH-OK has gone 9 -> 15 -> 15 -> 15 -> 15 -> 18. THE TExecuteFlags WALL IS CLEARED (2026-09-11, frankH): sysutils gained ExecuteProcess and TExecuteFlags, and cfileutl.pas:136 no longer stops anyone. It bought ZERO units -- a FIFTH null row -- and an A/B on ONE binary shows why: cfileutl, rgobj and aasmbase were all stopped at that SAME LINE, and they now stop at `unknown type: TDoubleRec` (x86_64/cpuinfo.pas:36) and `undefined variable (IsATTY)` (comptty.pas:66) respectively, the latter again ONE line reached by two units. BOTH NEW WALLS ARE NOW SETTLED TOO, SAME EVENING, AND BOTH LANDED ON THE UNIT CYCLE. termio.IsATTY was added (d57a1efaa) and rgobj+aasmbase moved to `comphook.pas:251 undefined variable (V_Status)`. I recorded that as the unit cycle, then CORRECTED myself to 'not the unit cycle, that ticket is done and its minimal shape passes' -- AND THE CORRECTION WAS ALSO WRONG. It IS the unit cycle, in an ORDER-DEPENDENT shape the fixed ticket's fixture structurally cannot express: CycleWaitUnit is a global and ParseUnitImplSection re-enters itself, so a unit named AFTER the cycle-closer in the same clause cleared the pending park. Both of my claims measured a real shape and generalised it to the bug; the quantifier was the invention each time. FIXED 2026-09-11, same evening, and the V_Status wall is CLEARED. TDoubleRec was NOT built: measured instead, and it buys zero, because cfileutl's implementation uses Comphook+Globals and `globals` alone already fails at that same V_Status; it was re-laned P and repriced 40->25 blocked-by the cycle. So THREE walls cleared or priced in one evening delivered every unit involved into ONE new wall -- which was then cleared too, the same evening, as the order-dependent residual of the unit cycle. globals, rgobj, aasmbase, comphook and cfileutl ALL now reach `unknown type: TDoubleRec` (x86_64/cpuinfo.pas:36), which is feature-b-rtl-has-no-tdoublerec, already in blocked-by and already repriced. MEASURED, AND THE SIXTH NULL ROW IS CONFIRMED -- A/B over all 207 units on TWO BINARIES differing by exactly 401c00f2b: BOTH-OK 21 before and 21 after, ZERO units newly compiling, ZERO regressed, and 101 of 207 units changed their first error -- ALL 101 from `undefined variable (V_Status)` and ALL 101 to `unknown type: TDoubleRec`. One wall into one wall, nothing scattered, half the corpus moved and the conversion rate was zero. TDoubleRec is now the first failure of 132 of 207 (64%). That is the largest single-wall transfer this umbrella has recorded and it is the cleanest possible statement of the queue-position finding: a wall's population counts units QUEUED behind it, never work. A SIXTH NULL ROW IS THE DEFAULT EXPECTATION FOR THE NEXT RE-RUN AND IT IS STATED HERE BEFORE THE RUN, not after: five walls in a row have converted at 0, 3 and 2 units, and every unit this one freed landed on the same next wall, which is the signature of a queue rather than a population. AND THE INSTRUMENT THIS UMBRELLA SAYS NOBODY BUILT ALREADY EXISTS: the compiler recovers up to MAX_REPORTED_ERRORS=20 semantic errors per unit, and tools/fpc_compiler_corpus_probe.sh pipes it through `head -1`. Taking that off shows the wall BEHIND the first one for free -- behind cfileutl's TDoubleRec sits `too many array initializer elements` at cpuinfo.pas:281 -- so the every-failure-per-subject census this umbrella has wanted for five null rows is a harness change, not a compiler feature. DO NOT RANK ANY OF THEM ON UNIT COUNT: attempt 7 measured the conversion rate of a cleared wall at three units. A second row went the same evening -- a set-valued record field (138604b5e), which is how tokens.pas writes its ~400-row token table -- and probe #12 says it bought TWO (tokens, rescmn) while eight more moved up to the TExecuteFlags wall. THREE WALLS, THREE JOINS, YIELDS OF 3 AND 2: a wall's population says how many units are QUEUED behind it, and the units that turn BOTH-OK are the ones for which it was the LAST wall. Near-disjoint sets; only the second is worth a number."
---

# Why this exists and what it replaces

Track P closed roughly twenty bugs tonight, ranked by `ready --track P`. That
ranking is a **backlog order**, not a **usage order**. This umbrella is the
instrument that produces a usage order: point pxx at FPC's source, and the first
failure is by definition the thing most in the way.

**It does not replace the P backlog — it re-ranks it.** Tickets the attempt hits
inherit this umbrella's prio through `effective_prio`; tickets it never reaches
were, by measurement, not blocking real-world Pascal.

# The target

FPC's compiler source, as shipped. Do not vendor it, do not reduce it, do not
fix it — this is a **corpus**, and the cheat licence that applies to
lekkerzeilen explicitly **does not apply here**: FPC is not ours, and bending it
would destroy what the measurement is for.

# How to grow this (the only supported method)

1. Point `compiler/pascal26` at a translation unit of FPC's source.
2. Record the FIRST failure. Reduce it to a minimal repro before filing —
   a first-error reading is a LOWER BOUND, not a work estimate, and tonight
   produced three cases where reducing changed what the bug WAS.
3. File it in `backlog-pascal`, wire it here with `blocked-by`, move to the
   next unit.
4. Say in each ticket which FPC unit and line produced it.

**Do not triage the existing P backlog into this umbrella.** If an existing
ticket turns out to be what the attempt hit, wire that one — membership is an
edge, not a folder, and one ticket can sit under several umbrellas.

# Two things measured 2026-09-09 that set expectations

- **The self-host fixedpoint proves nothing here.** `compiler.pas` is a
  deliberately procedural subset; Track P's coverage of it is partial, which is
  worse than none because it looks total. FPC's source uses the whole language.
- **Do not chase FPC parity, chase compiling FPC.** Us accepting what FPC
  rejects is not a defect. The question this umbrella asks is only ever "does
  the source compile and run correctly", never "does our diagnostic match".

# Sibling targets, same mode

`umbrella-compile-and-run-dosbox` (prio 50, **zero blockers — nobody has
attempted it**) and the busybox family, which has eleven open tickets across
five folders and **no umbrella of its own**. Both are the same instruction:
attempt the target, let the failures rank themselves.

# Attempts

## 2026-09-09, frankH — attempt 1: `uses cutils`

First failure: `constexp.pas:164`, `undefined variable (internalerrorproc)`.
Reduced to 8+9+4 lines and filed as
[[bug-p-a-unit-cycle-closed-through-an-implementation-uses-cannot-see-the-other-interface]]
(p60). A unit cycle closed through an `implementation uses` clause cannot see
the other unit's interface. **25 of 162 units** in `fpc-trunk/compiler` close
such a cycle, so this is structural in the corpus, not incidental — and nothing
behind it can be measured until it moves.

Pre-existing, not a regression: pin v399 gives the identical error.

## 2026-09-09 — the owner's framing, which bounds this umbrella

> *"the challenge is just to compile FPC as a proof of pudding. we don't target
> any advanced compatibility. i can see what FPC is doing, sortof. we don't
> care. FPC is a great compiler and we have other goals, the common thing is
> pascal and that we sayd we target FPC's dialect as de-facto standard."*

**This is a PROOF, not a compatibility programme, and the distinction is the
one most likely to be lost by whoever attempts it.** Pointing pxx at 400k lines
of another compiler's source will surface a great many differences. Almost none
of them are ours.

**A finding belongs under this umbrella only if it stops correct Pascal
compiling or running.** Not because FPC does it differently, not because a
diagnostic differs, not because an intermediate has a different type. If the
source compiles and the program behaves, there is nothing to file — and the
temptation to file it anyway is exactly what turned 5035 tickets into 467 open
ones.

**Binary interop with FPC is NOT a goal** — settled the same day in
`decide-how-a-hand-built-com-interface-becomes-callable`, now in `done/`. Do not
rank anything here on exchanging objects with FPC-compiled code, sharing its
representations, or linking against its output.

## 2026-09-09, frankH — attempt 2: THE WHOLE CORPUS, and the invocation was wrong

**READ THIS BEFORE ANY NUMBER IN ATTEMPT 1.** Attempt 1 was invoked as
`pascal26 -Mobjfpc -Fu<compiler> -Fi<compiler>`, and that is not how FPC's
compiler is built. Under it, `globtype.pas:115 unknown type: PInt` looked like a
frontend bug and was on its way to being filed. It is not one: `PInt` is
declared only inside `{$ifdef cpu64bitaddr}` arms, `fpcdefs.inc` derives that
from the CPU define, and FPC's own `Makefile.fpc:381` passes `-d$(CPC_TARGET)`.
**pxx already has the flag for exactly this** — `--mimic-fpc-compiler`
(`feature-mimic-fpc-compiler-define-profile`), which supplies the FPC identity
defines *plus* the one CPU define fpcdefs.inc derives the other forty from.

**The corpus-attempt rule this produces, and it is the transferable half:**
compile the corpus the way its own BUILD compiles it, and prove it by running
that build's compiler as an ORACLE on the same invocation. Four of the ten first
failures in attempt 1 were mine, not pxx's, and one of them (`ccharset`) fpc
itself refuses under that invocation — a unit the oracle cannot compile can
never be evidence about us. Every row below is therefore `fpc` first, `pxx`
second, same flags:

    fpc      -Mobjfpc -dx86_64 -Fu{C} -Fu{C}/x86_64 -Fu{C}/systems -Fu{C}/x86 \
                                -Fi{C} -Fi{C}/x86_64 -Fi{C}/x86
    pascal26 -Mobjfpc --mimic-fpc-compiler   <the same -Fu/-Fi set>

Driver: one `program d; uses <unit>; begin end.` per unit, all 207 `.pas` in
`fpc-trunk/compiler`. Script committed as `tools/fpc_compiler_corpus_probe.sh`, so the method is
runnable rather than described; it refuses to run at all when `fpc` is absent,
because without the oracle a PXX-FAIL row is not evidence.

### The distribution, measured at `24dbb0b37`

| | |
| --- | --- |
| units | 207 |
| **compile under both** | **9** — compinnr dbgdwarfconst dwarfbase fpchash globtype macho symconst version wasmbase |
| oracle refuses (not evidence about us) | 10 |
| pxx stops | 188 |

First failures, by count. **These are first-failure counts and therefore LOWER
BOUNDS on nothing and UPPER BOUNDS on nothing** — a unit that stops on the cycle
may stop on the next cause after it moves, and 144 units clearing does not mean
144 units compiling. What the count IS good for is ORDER.

| n | first failure | ticket |
| --- | --- | --- |
| 144 | `undefined variable (internalerrorproc)` | [[bug-p-a-unit-cycle-closed-through-an-implementation-uses-cannot-see-the-other-interface]] |
| 19 | `{$if}` over a source `const` or a source type alias | [[bug-p-a-conditional-directive-cannot-read-a-constant-or-a-type-the-source-declares]] |
| 8 | `an object type cannot have a constructor` | [[feature-p-legacy-value-object-types]] |
| 3 | `undefined variable (bitsizeof)` | none — see below |
| 2 | `expected field name in record constant` | none yet |
| 3 | `uses: unit source not found` (unixcp, heaptrc, charset) | RTL units, not frontend |
| 2 | `conditional directive: malformed expression` / `expected operator` | none yet |
| 1 each | `undefined variable (align)`, `undefined variable (IsATTY)` | none yet |

### What moved this session, attributed rather than assumed

Two fixes landed. `588f18717` folds FPC's `Sar*` intrinsics; `24dbb0b37` lets a
subrange bound be a folded call (`low(TCGLoc)..pred(LOC_CREFERENCE)`,
cgbase.pas:63). Re-running the whole probe before and after the second one, the
diff is **exactly five rows and no others**: aasmcfi, cgbase, nbas, ncgmem and
ncgnstmm move from `cgbase.pas:63 unknown type: low` to `cgbase.pas:381 an
object type cannot have a constructor`, 318 lines further into the same file.
**No unit newly compiles**, and saying that is the point: a corpus delta is easy
to quote as progress and the honest unit of progress here is a wall, not a line
number.

### `bitsizeof`, banked rather than filed, with the whole answer

`bitsizeof(x)` is an FPC intrinsic like `Sar*` — `compinnr.pas:85`,
`in_bitsizeof_x` — and it stops constexp, cgobj and ppu. **It is exactly
`SizeOf(x) * 8` for every type pxx can express**, and that is measured, not
assumed: fpc answers 32/64/32/8 for `bitsizeof` of a LongInt, an Int64, the
LongInt type name and Byte, and the one place the two would differ is a
`bitpacked` field (fpc says 2 for `a: 0..3`), which **pxx has no `bitpacked` at
all** to reach — `type T = bitpacked record` is `unknown type: bitpacked`.
So the desugar has no wrong answer available today and WILL when bitpacked
lands; whoever writes it should say so in the comment.

It is not a one-line fix like `Sar*` for one reason worth recording: `SizeOf`'s
arm in `pasparser_expr.inc` runs ~700 lines with **six** separate
`AllocNode(AN_INT_LIT)` exits, so `* 8` is six edits, which is the shape this
repo keeps finding a missed copy in. The honest version unifies those exits
first.

### What the attempt says about the two big walls

The cycle is not merely the largest, it is 77% of the corpus, and it is
structural: FPC splits `uses` into two clauses precisely so units can be
mutually recursive. Nothing behind it can be measured. The conditional-directive
family is second and is the one that is *shaped* like work already done here —
two forwarded questions of exactly its kind already exist beside it.

## 2026-09-09, frankH — attempt 3: the conditional-directive family, and what it uncovered

Two commits, `abc681636` (read a source `const`, follow a type ALIAS through
`sizeof`) and `fcbe280b7` (the two probe defects underneath it). **The whole
probe was re-run before and after each**, so both deltas below are per-unit
diffs and not category arithmetic.

| | 24dbb0b37 | abc681636 | fcbe280b7 |
| --- | --- | --- | --- |
| compile under both | **9** | **9** | **9** |
| oracle refuses | 10 | 10 | 10 |
| pxx stops | 188 | 188 | 188 |
| — of those, the conditional-directive family | **26** | 3 | **3** |
| — of those, the unit cycle | 144 | 155 | **158** |

**NO UNIT NEWLY COMPILES, across both commits.** That is the third time this
umbrella has had to say it and it stays the honest unit of progress: a corpus
delta is a wall moving, not a program building, and everything behind the
26 rows was standing in the unit cycle's queue.

**`abc681636` — 25 units changed and every one of them was a
conditional-directive first failure.** No row moved that was not in that
family, which is what an attributed delta looks like. 11 went to the unit
cycle, 5 to `ALU not defined` (a wall further into the same files), 5 to
`Unsupported tcompilerwidechar size`, 2 to `bitsizeof`, 1 to `unterminated
conditional directive` and 1 (ncnv) from one conditional row to another.

**`fcbe280b7` — 12 units changed, all forward.** `ALU not defined` (5 units)
and `unterminated conditional directive` (1) cleared entirely.

### The two probe defects, because they are the transferable half

Neither was new with the const/alias questions; both are older and
`{$if declared(X)}` had the first one first.

- **A probe launched inside a conditional unbalanced the `{$if}` stack.** The
  walk scans the WHOLE token stream for `uses`, so a unit being lexed through
  `LexAppend` finds its PARENT's `uses <thisunit>` and **re-lexes the file it
  is currently inside**, from the outer file's conditional depth. At depth 0
  the arithmetic balances and nothing shows; one conditional deep, the outer
  file is refused at its own last line. FPC's `entfile.pas` — 2131 lines, 170
  openers, 170 `{$endif}`, perfectly balanced — reduced to 14+5+3 lines.
- **The probe never expanded the probed unit's `{$I}` includes**, which its own
  header said it did and is the reason it LEXES rather than scanning text.
  `ParseUsesUnitBody` calls `ExpandIncludes` before the real `LexAppend`; the
  probe called `LexAppend` alone. So a name in an `.inc` was invisible, and so
  was every name behind a define an `.inc` SETS: `globtype.pas` declares
  `PUint = qword` inside `{$ifdef cpu64bitaddr}`, `fpcdefs.inc` derives
  `cpu64bitaddr`, and the walk `TConstPtrUInt -> PUint -> qword` therefore
  stopped one hop short. The 18 `sizeof` rows of the 26 named five different
  types -- 11 `bestreal`, 3 `TConstPtrUInt`, 2 `tcompilerwidechar`, 1
  `aintmax`, 1 `bestrealrec` -- and only the `TConstPtrUInt` chain needed the
  includes; the rest were answered by the const/alias commit alone. Said that
  way because "18 rows of one kind" is exactly the summary that would have hidden
  the split.

### `Unsupported tcompilerwidechar size` is the `charset` row, not a frontend bug

7 units stop there and they are ONE cause, measured rather than inferred:
`ncon.pas:968` is FPC's own `{$error}` in the `{$else}` arm of
`{$if sizeof(tcompilerwidechar) = 2}`; `tcompilerwidechar = word` lives in
`widestr.pas:35`; `widestr` uses **`charset`**, which is an FPC **RTL** unit
and is not on the probe's unit path. Two controls:

- a local stand-in unit declaring the identical `tcompilerwidechar = word`
  answers `two`, so the alias walk is not the problem; and
- with `fpc-trunk/rtl/inc` added to `-Fu`, the `{$if}` resolves and the first
  failure moves INTO `charset.pp`, at `DirectorySeparator` — an FPC `System`
  constant that appears nowhere in pxx's `lib/` or `compiler/`.

So these 7 belong on the same row as `uses: unit source not found: charset`,
and the next measurable step for them is not the frontend: it is whether pxx
compiles FPC's RTL at all. **That is a different corpus and it should be
decided as one before anybody starts adding System constants one error at a
time.**

### What is left of the conditional-directive family: 3 units, 2 shapes

Filed as
[[bug-p-a-conditional-directive-cannot-read-a-const-whose-value-is-not-an-integer-literal]]
— set membership over a set-valued const (`nld.pas:700`, and ncnv reaches the
same directive through `uses nld`) and a const whose value is a folded call
(`RS_INVALID = high(tsuperregister)`, `cgbase.pas:400`, asked by
`rgobj.pas:1728`). Both are behind the unit cycle anyway.

### `make test-fpc` IS NOT THIS TARGET, and it has never produced a verdict row

Two separate traps, and the second is the one that will catch a later
attempt. **`test-fpc` runs FPC's TEST SUITE; this umbrella compiles FPC's
COMPILER.** They share a name and nothing else — the suite is thousands of
small conformance programs, the compiler is 207 mutually-recursive units, and
a green on one says nothing about the other. **And `test-fpc` is in NO TIER**
(frankuser, 2026-09-09, filed as
`bug-t-six-real-program-jobs-are-in-no-tier-so-they-never-run`, T p65, with
duktape, quickjs, chess-perft, sqlite-parity and wasm32): it is not skipped
and not failing, no tier invokes it, so it has produced zero rows ever. A
green from running it by hand is a claim about that one run on that one tree.

So: do not reach for `make test-fpc` to measure this umbrella, and do not read
its absence from the tstate archive as a pass.

## 2026-09-10, frankH — attempt 4: the two biggest walls, and neither bought a unit

Two fixes, each with the WHOLE probe re-run before and after it, so both deltas
below are per-unit joins and not category arithmetic.

| | `590e7c100` | `6e8a821db` (cycle) | `7e4f69a34` (bitsizeof) |
| --- | --- | --- | --- |
| units | 207 | 207 | 207 |
| **compile under both** | **9** | **9** | measured below |
| oracle refuses | 10 | 10 | |
| pxx stops | 188 | 188 | |

| first failure | `590e7c100` | after the cycle fix |
| --- | --- | --- |
| `undefined variable (internalerrorproc)` — the unit cycle | **158** | **0** |
| `undefined variable (bitsizeof)` | 5 | **163** |
| `an object type cannot have a constructor` | 8 | 8 |
| `Unsupported tcompilerwidechar size` | 7 | 7 |
| `expected field name in record constant` | 2 | 2 |
| `conditional directive: expected operator` | 2 | 2 |
| `uses: unit source not found` (unixcp, heaptrc, charset) | 3 | 3 |
| `undefined variable (align)` / `(IsATTY)` | 1 each | 1 each |
| `RS_INVALID` has no integer value | 1 | 1 |

**Exactly 158 units moved, every one of them from the cycle to `bitsizeof`, and
nothing else moved at all.** A join on the unit name says so.

### The number to distrust here is the one that did NOT move

**BOTH-OK stayed at 9 across the largest single fix this umbrella has had.**
76% of the corpus was standing behind the unit cycle and the next wall was
immediately behind it, so a 158-row delta bought no unit. That is the shape to
expect from a corpus attempt and it is why this file reports walls rather than
line numbers: a per-unit diff of 158 rows is easy to quote as progress, and the
honest unit of progress is a wall.

### `bitsizeof` was banked here with its whole answer and it held up

The banked note said `SizeOf(x) * 8`, no wrong answer reachable because pxx has
no `bitpacked`, and not a one-liner only because SizeOf's arm has six
`AllocNode(AN_INT_LIT)` exits — *"the honest version unifies those exits
first"*. All three were right. The exits are now one (`EmitSizeOfResult`) and
the multiply exists once.

Banking the whole answer rather than filing a ticket was the right call for a
five-line desugar behind a six-copy refactor, and it is worth saying why it
worked: the note carried the MEASUREMENT (fpc's four answers), the BOUNDARY
(`bitpacked`, and that it is unreachable) and the COST (six exits). A ticket
saying "implement bitsizeof" would have carried none of them.

### What the attempt says now

The corpus is no longer dominated by one structural wall. After `7e4f69a34`
the distribution is measured in the row below this section; whatever it says,
the next causes are all SMALL — the largest before this attempt was 8 — which
means the next rung of this umbrella is a different kind of work from the last
two: several unrelated causes rather than one that everything queues behind.

## 2026-09-10, frankH — attempt 5: the System routines, and a THIRD consecutive null row

Two more walls cleared and **BOTH-OK did not move at all, for the third attempt
running.** That is the number this section is about.

### What landed

| sha | wall | units it was the first failure of |
| --- | --- | --- |
| `959468420` / `0dfa0b298` | `unknown type: PSizeUint` | 150 |
| `dbb96cdb6` | `undefined variable (IndexQWord)` | 96 |

Both are FPC **System-unit surface**, not dialect features — the same class as
`Prefetch`, which is already in `builtin.pas` for exactly this reason. The
Index/Compare family went in beside it: `IndexByte`, `IndexWord`, `IndexDWord`,
`IndexQWord`, `CompareWord`, `CompareDWord`. `TFPList.IndexOf`
(`cclasses.pas:890-895`) selects the DWord or QWord arm by pointer width under
a `{$if}`, so **both arms must resolve for either to compile** — a family with
holes in it is not half-working, it is not working.

### The measurement

Whole probe re-run at each sha, `fpc` as oracle, per-unit join rather than
category arithmetic.

| | probe #8 @ `0dfa0b298` | probe #9 @ `dbb96cdb6` |
| --- | --- | --- |
| BOTH-OK | 15 | **15** |
| ORACLE-NO | 10 | 10 |
| PXX-FAIL | 182 | 182 |

Join: **exactly 96 units changed their row, every one of them
`IndexQWord` -> `unaligned`, and nothing else moved.** The BOTH-OK set is
byte-identical between the two runs, not merely the same size:

```
cdynset compinnr constexp cstreams cutils dbgdwarfconst dwarfbase fpchash
globtype macho optbase symconst systems version wasmbase
```

### First failures now

| n | first failure |
| --- | --- |
| 150 | `undefined variable (unaligned)` — `cclasses.pas:1327` |
| 6 | `Unsupported tcompilerwidechar size` |
| 7 | `an object type cannot have a constructor` (two line numbers) |
| 4 | `expected field name in record constant` |
| 3 | `unknown type: d` |
| 1 each | `IsATTY`, `align`, `swapendian`, `unixcp`, `RS_INVALID` |

### The number to distrust, again, is the one that did NOT move

Three attempts in a row have cleared the single largest wall and bought **zero**
units: 158 units moved for the unit cycle, 96 for the Index family, and BOTH-OK
went 9 -> 15 -> 15 -> 15. The 15 was bought by `bitsizeof` alone.

The reading is not "the fixes did nothing". It is that **in this corpus the
walls are STACKED, and the depth is what nobody has measured.** Every unit that
cleared `IndexQWord` landed on `unaligned` — the same file, four hundred lines
further down. Clearing wall N reveals wall N+1 in the same dependency, so the
first-failure histogram is a picture of ONE unit's contents (`cclasses.pas`,
which nearly everything uses) far more than of the corpus's difficulty.

**So stop ranking this umbrella's blockers by how many units name them.** 150
units naming `unaligned` is one call site in one shared unit; it says almost
nothing about how much work stands between here and a compiling corpus. The
honest instrument for that question is a probe that reports EVERY failure in a
unit rather than the first, and nobody has built one. Until then, the count is
a queue position, not a size.

Filed from this attempt:
[[feature-p-unaligned-is-a-transparent-lvalue-not-a-function]] — and note it is
NOT a `builtin.pas` job like the last two looked: 275 call sites in the corpus
and some are assignment targets, so a function-shaped fix clears all 150 units
and still fails on `ogomf`, `owomflib` and `entfile` for the identical spelling.

## 2026-09-10, frankH — attempt 6: the prediction, tested the same hour it was written

`b9c8fc160` landed `unaligned`. Probe #10, whole corpus re-run, per-unit join:

**exactly 150 units changed their row, every one `unaligned` -> `Finalize(x, n)`,
nothing else moved, BOTH-OK byte-identical at 15 for the third run running.**

That is the FOURTH consecutive null row, and it is the sharpest one, because
the section above predicted it in this form: the walls are stacked inside
`cclasses.pas` and the count measures queue position rather than size. Three
consecutive walls, one file:

| probe | wall | line in `cclasses.pas` | units |
| --- | --- | --- | --- |
| #8 | `undefined variable (IndexQWord)` | 895 | 96 |
| #9 | `undefined variable (unaligned)` | 1327 | 150 |
| #10 | `Finalize(x, n)` — the element-count form | 1726 | 150 |

`TFPHashList.Clear` calls `Finalize(FItems^, FCount)`. Each fix delivered its
entire population intact to a wall a few hundred lines further down the same
file.

**This is now the umbrella's most reliable finding and it should shape how the
next seat works it.** Fixing the top of the histogram is nearly free of value
per fix while `cclasses` is unfinished — the honest unit of work is *"make
`cclasses.pas` compile"*, not *"clear the 150"*. The instrument that would say
how far that is reports EVERY failure per unit rather than the first, and it
still does not exist; building it is worth more than the next four walls.

Promoted to CLAUDE.md from here, on the recurrence test: frankB's lekkerzeilen
umbrella produced the same shape independently (six import walls across two
passes, modules-compiling moved by zero both times) — two corpora, no shared
code, five null rows between them.

## 2026-09-10 — the ten ORACLE-NO units, named, because the category reads as a scandal

The owner asked, reasonably, whether this umbrella was claiming *"fpc can't
compile its own units"*. It is not, and the category name invites that reading.
Measured by running only the oracle half of
`tools/fpc_compiler_corpus_probe.sh` (207 fpc compiles, no pxx):

| unit | fpc's own message | why |
| --- | --- | --- |
| `pp` | `Syntax error, "UNIT" expected but "PROGRAM" found` | **it is a PROGRAM** — FPC's compiler main. `uses pp` is meaningless |
| `cg64f32` | `Identifier not found "tcg64"` | 32-bit codegen; `tcg64` exists only on a 32-bit target |
| `ogomf` | `RELOC_ABSOLUTE16` | 16-bit x86 object format |
| `ogrel` | `RELOC_ABSOLUTE_HI8` | AVR |
| `ogwasm` | `TWasmBasicType` | wasm |
| `oglx` | `tobjectinput` | platform-conditional |
| `browcol` | `TCallbackFunBoolParam` | platform-conditional |
| `impdef` | `dirstr` | platform-conditional |
| `cepiktimer` | `Cannot open include file "../../epiktimer/epiktimer.pas"` | external package, not installed |
| `ccharset` | `fpcdefs.inc(1,2) Mode switch "OBJFPC" not allowed here` | **the probe's own `-Mobjfpc` colliding with the include** |

**Nothing here is fpc failing to build fpc.** The probe fixes `-dx86_64`; build
FPC for i386 and `cg64f32` compiles, for AVR `ogrel`, for wasm `ogwasm`. The
exclusion exists so a unit the ORACLE rejects under OUR flags can never be
counted against us — which is the right design and is why attempt 1 had four
false findings before it existed.

### Two of the ten are OURS, not the corpus's

`pp.pas` is a program and should be excluded **by name**: counting it inflates
the denominator by one and it can never pass, so it is a permanent
can-never-be-green row sitting in the corpus total. `ccharset` is a flag
collision the probe creates itself — `-Mobjfpc` on the command line against an
include that sets its own mode switch — and may well compile once the probe stops
forcing the mode it is already getting from `fpcdefs.inc`.

**So the honest shape is 206 units: 8 genuinely out of scope for an x86-64
probe, 15 BOTH-OK, 182 PXX-FAIL.** Worth fixing in the probe rather than
re-explaining every time someone reads the category — a number that needs a
paragraph of defence each time it is quoted is a number with the wrong
denominator.

## 2026-09-11, frankS — attempt 7: `cclasses.pas` compiles, and the null row ends at four

Probe #11 at `e013c4344`, binary `79b76b2cc67f`, whole corpus, `fpc` as oracle.

| | probe #10 @ `b9c8fc160` | probe #11 @ `e013c4344` |
| --- | --- | --- |
| BOTH-OK | 15 | **18** |
| ORACLE-NO | 10 | 10 |
| PXX-FAIL | 182 | 179 |

**Join against attempt 6's BOTH-OK set, which was listed there by name: all
fifteen are still present and the three added are `cclasses`, `crefs`,
`rabase`.** `crefs` is `uses globtype, cclasses`; `rabase` is `uses cclasses,
systems`. So the delta is exactly the unit that was unblocked plus its two direct
dependents, and **nothing else moved** — the same per-unit join the earlier
attempts used, and the reason it is worth the extra minute is that a +3 with a
different membership would have meant something else entirely.

### What it took, and it was two bugs in one file

The instrument attempt 6 asked for — one that reports EVERY failure per unit
rather than the first — turned out not to be a wrapper. `Finalize(x, n)` was
raised through `Error()`, which HALTS, so every later wall in the same file was
structurally invisible. Converting that one site to `ErrorRecover` took
`cclasses` from ONE reported failure to THREE, and the second was real and
pre-existing:

1. **[[bug-p-a-method-parameter-typed-through-a-forward-pointer-alias-never-matches-its-own-body]]**
   (`ee560d0ad`) — a method parameter typed through a forward pointer alias never
   matched its own body, so the body died at codegen with `unresolved forward`
   naming a file the author never wrote.
2. **[[feature-p-the-element-count-form-of-initialize-and-finalize]]**
   (`d095cb08d`) — the wall itself, which was a DELIBERATE refusal recorded in
   `done/feature-a-implement-initialize-and-finalize-over-the-arc-helpers`.
   That refusal is right about *ignoring* the form and is not an argument against
   implementing it.

`ok: dpxx [code=536232B data=109348B bss=93392B procs=1487]`.

### The four null rows were a queue and the queue emptied — but NOT for free

Attempt 6's finding stands and this attempt is its confirmation, not its
refutation. The 150 did **not** become 150 BOTH-OK; they became 119 units
stopped at the next wall, in a different file. **Three of 150 is what "clearing
the wall the 150 were on" was actually worth**, and that is the number to quote
against any future proposal to rank a blocker on its unit count.

### First failures now

| n | first failure |
| --- | --- |
| 119 | `unknown type: TExecuteFlags` — `cfileutl.pas:136`, in its INTERFACE |
| 18 | `an object type cannot have a constructor` |
| 10 | `expected field name in record constant` — `tokens.pas:378` |
| 10 | `Unsupported tcompilerwidechar size` |
| 6 | `uses: unit source not found: charset` |
| 4 | `unknown type: d` — `sizeof(d)` of a PARAMETER inside a local type decl |
| 4 | `unknown type: TDoubleRec` — `x86_64/cpuinfo.pas:36` |
| 2 | `conditional directive: expected operator` |
| 1 each | `unixcp`, `heaptrc`, `swapendian`, `align`, `IsATTY`, `RS_INVALID` |

**`TExecuteFlags` is not a parser gap** — it is `sysutils`, and it was already
filed by frankH on 2026-09-09 as
[[feature-b-sysutils-has-no-executeprocess-and-no-texecuteflags]], back when it
was the frontier for a handful of units rather than for 119. Every line of that
diagnosis still holds and none of it needed re-deriving; it has a dated note
with the new count and nothing else. The hard half (`ExecutePipeline` /
`PalVforkAndExec`) is already written in the same unit, and **a type-only stub is
worse than nothing** — `cfileutl`'s implementation calls `ExecuteProcess`, so the
type alone just moves the failure to link time.
**Do not rank it on 119**: this umbrella's own most reliable finding says that
number is a queue position, and attempt 7 just measured the conversion rate at
three units per wall.

### One row is already gone, and it is recorded here so the next join is honest

`expected field name in record constant` was reduced and fixed the same hour —
[[bug-p-a-set-valued-record-field-cannot-be-written-in-a-record-constant]]
(`138604b5e`): FPC's `tokens.pas` writes `keyword:[m_none]` in ~400 record
constants and the set arm of `TryParseInitValForm` had been written out by hand
in the const-ARRAY loop and given to no other caller. `tokens.pas` compiles.
**This table is probe #11's.** Probe #12 is below and it is the current one.

### Probe #12 @ `4c7c88d36`, the same evening: 18 -> 20, and the ratio held a third time

| | #10 @ `b9c8fc160` | #11 @ `e013c4344` | #12 @ `4c7c88d36` |
| --- | --- | --- | --- |
| BOTH-OK | 15 | 18 | **20** |
| ORACLE-NO | 10 | 10 | 10 |
| PXX-FAIL | 182 | 179 | 177 |

Join again: **all eighteen of #11's BOTH-OK units are still there and the two
added are `tokens` and `rescmn`** — the two units that carried a set-valued
record field themselves. `rescmn` is `uses Systems` and opens with
`res_elf_info : tresinfo = (...)`. The other **eight** of the ten that stopped at
`expected field name in record constant` moved to `unknown type: TExecuteFlags`,
which is why that row went 119 -> 127 while nothing about `TExecuteFlags`
changed.

**Three walls, three joins, three small numbers: 3, then 2.** A wall's unit
count has now predicted its yield wrongly five times running, and the two
measurements in this attempt are the first where the yield was positive at all —
which makes them the strongest form of the same finding, not a counterexample to
it. The useful reading: **a wall's population tells you how many units are
QUEUED behind it; the units that become BOTH-OK are the ones for which it was
the LAST wall.** Those are near-disjoint sets, and only the second is worth a
number.

### First failures now (probe #12)

| n | first failure |
| --- | --- |
| 127 | `unknown type: TExecuteFlags` — `cfileutl.pas:136`, in its INTERFACE |
| 18 | `an object type cannot have a constructor` |
| 10 | `Unsupported tcompilerwidechar size` |
| 6 | `uses: unit source not found: charset` |
| 4 | `unknown type: d` — `sizeof(<a PARAMETER>)` in a const expression |
| 4 | `unknown type: TDoubleRec` |
| 2 | `conditional directive: expected operator` |
| 1 each | `unixcp`, `heaptrc`, `swapendian`, `align`, `IsATTY`, `RS_INVALID` |

`unknown type: d` is `entfile.pas:371`, `array[0..sizeof(d)-1]` where `d` is the
enclosing function's PARAMETER. `ConstEvalFactor`'s `sizeof` arm resolves a TYPE
NAME only and says so in its own comment; the expression path handles a variable
and `SizeOf(d)` in a statement answers 8 correctly. Reduced to ten lines and
left unfixed here rather than folded in — the honest fix is narrow but it is in
a 300-line intrinsic and deserves its own pass.

## 2026-09-11, frankH — two blockers closed, and the wall census gets a fourth null row

Both were taken from this umbrella's `blocked-by`, both are Track P, and the
combined corpus movement is **one unit advanced to the next wall and zero units
compiling.** That is the fourth independent time this umbrella has measured that
shape, and it is worth one line rather than another paragraph: the finding is no
longer news, it is the baseline expectation.

**`bug-p-sizeof-of-a-variable-is-not-folded-in-a-constant-expression`** —
`sizeof(<a variable>)` in a const expression (FPC entfile.pas:371). Fixed; 4
units stopped there and none of them compiles now either.

**`bug-p-a-conditional-directive-cannot-read-a-const-whose-value-is-not-an-integer-literal`**
— this one was **two defects plus a fourth hop the ticket had not traced**, and
that is the part worth carrying forward:

- pxx did not SHORT-CIRCUIT `and` in a `{$if}`. FPC's `declared(X) and (X<>Y)`
  idiom exists BECAUSE it short-circuits, and a shunting-yard applies the
  parenthesised comparison first. Nobody had filed it. It is a real bug with an
  oracle and it moves **zero** units, because 17 of FPC's 18 cpubase files DO
  declare `RS_STACK_POINTER_REG` — the portable idiom is portable, so the
  portable path is nearly never taken in this corpus.
- The const door then needed four hops, because the LEFT operand chains too:
  `RS_STACK_POINTER_REG = RS_RSP` across two units, and `high()` over a
  distinct-type alias. **rgobj CLEARS this wall** and stops at cfileutl.pas:136,
  which is `TExecuteFlags` — the 127-unit wall already at the top of this
  umbrella.
- `nld` and `ncnv` did NOT move; they are the set-membership shape, now split
  out as
  [[bug-p-a-conditional-directive-cannot-evaluate-in-over-a-set-constant]]. They
  are also **one directive, not two** — ncnv's interface `uses nld`.

**THE SPLIT IS THE TRANSFERABLE PART.** One ticket carried both shapes and their
sizes differ by an order of magnitude: the half that landed reused walks that
already existed and added no value kind, while the half split out needs a fourth
value kind on the directive stack, set-union folding, enum-member resolution and
an `in` operator the grammar does not have. A summary cannot be true about both,
and this umbrella ranks by `blocked-by` edges — so a mixed ticket prices the
cheap half at the expensive half's cost, in the one place where the price is what
gets read.

## The every-failure census, 2026-09-16 (binary `e790ec9e027f` at `9281da35b`)

**Run it as** `PXX_CORPUS_DETAIL=<dir> tools/fpc_compiler_corpus_probe.sh`. The
probe has had that flag and `errs=N` since 2026-09-11 — **this umbrella's own
headline still said nobody had built the instrument, and a seat nearly rebuilt
it.** Fixed above.

**Totals:** 21 BOTH-OK · 10 ORACLE-NO · 176 PXX-FAIL. BOTH-OK unchanged at 21,
as expected — nothing landed for P between probes.

**First-failure histogram** (still ranks by queue position — do not rank on it):

| n | first failure |
| --- | --- |
| 132 | `unknown type: TDoubleRec` |
| 18 | `an object type cannot have a constructor` |
| 10 | `Unsupported tcompilerwidechar size` |
| 6 | `uses: unit source not found: charset` |
| 4 | `undefined variable (entryreal_bytes)` |
| 2 | `conditional directive: expected operator` |

**The result the histogram cannot show, and the reason for the detail flag:**
of the 132 units whose FIRST failure is TDoubleRec, **0 have it as their ONLY
failure** and **all 132 also hit `too many array initializer elements` — and
nothing else.** Error counts per unit: 38 units report 1, **132 report exactly
2**, and only one unit anywhere reaches `MAX_REPORTED_ERRORS`. So the two-error
finding is real and not a truncation artefact.

**Both walls are `x86_64/cpuinfo.pas`, lines 36 and 281.** That is the
`cclasses.pas` pattern again — one file's contents wearing the shape of a
population — and it is the third time this umbrella has recorded it.

**Prediction for the next run, stated before it:** clearing BOTH lands the 132 on
a **third wall in the same file**, not on 132 compiling units. A complete
*reported* failure set is not a guarantee of compilation — `ErrorRecover` carries
past SEMANTIC failures, and a halting diagnostic later in the unit would never
appear. That is the honest caveat and it should not be dropped when this is
quoted.

---

## 2026-09-16 (frankS) — the seventh null row, and the third wall is REAL but NOT in the same file

`bug-p-an-array-constant-with-a-set-element-type-cannot-be-initialised` is fixed
(`14df2066b`). Measured what that delivered, and measured the prediction that was
put on record before the work, which is the part worth keeping.

**Three arms, same probe, 207 units, pxx-only (no fpc oracle — read the DELTA
between columns, never the absolute count):**

| arm | compiler | cpuinfo walls | units OK | total errors |
| --- | --- | --- | --- | --- |
| `base` | pre-fix | both present | **21** | 396 |
| `fix` | post-fix | TDoubleRec only | **21** | 396 |
| `stub` | pre-fix | both stubbed out | **21** | 256 |

**UNITS COMPILING MOVED BY ZERO IN BOTH DIRECTIONS — including with BOTH walls
removed.** That is the seventh null row and it is consistent with every previous
one. 138 units report exactly two errors, `TDoubleRec` first.

**THE FIX WORKED AND THE COUNT CANNOT SEE IT.** `base` and `fix` are identical
unit-by-unit *and* identical in total error count, which reads as "nothing
happened". It is not what happened. Checked one unit directly:

```
aasmbase, pre-fix : pascal26:36  unknown type: TDoubleRec
                    pascal26:281 too many array initializer elements
aasmbase, post-fix: pascal26:36  unknown type: TDoubleRec
                    pascal26:35  an object type cannot have a constructor
```

The array error is gone and a **different** error took its slot. All 138 units
traded one wall for the next, so the count held at 2 and the first-error
histogram — which is what the `PXX_CORPUS_DETAIL` summary reports — held at
`TDoubleRec`. **An error COUNT is not an error IDENTITY**, and a wall census
compared on counts will report a successful fix as a null result. Compare the
message sets, not the totals.

**The prediction, scored honestly.** It was: *"clearing both lands the 132 on a
third wall in the same file."* Half right, and the wrong half matters.

- **RIGHT that a third wall swallows the population.** With both walls stubbed,
  **156 units** hit `an object type cannot have a constructor`
  (`bug-p-object-value-types-standard-meaning`, already ticketed) — up from 18,
  so 138 arrived there exactly as predicted.
- **WRONG that it is in the same file.** With both stubbed, `cpuinfo.pas`
  **compiles clean**. There is no third wall in that file; the next one is
  further down each unit's own dependency chain.

That distinction is worth keeping because it changes what the next fix should
be. "Another wall in cpuinfo.pas" would mean keep grinding that file; "one
shared wall one file further on" means the next lever is
`bug-p-object-value-types-standard-meaning`, which now gates 156 of 207 units
and is the largest single wall this corpus has.

**And the ranking caveat still applies to that 156, unchanged.** It counts units
QUEUED, not work, and this umbrella has now converted seven walls at a yield of
zero additional compiling units. Predict before the next re-run; a null row is
only information to someone who said what they expected.

**`ErrorRecover` caveat, carried forward.** A complete *reported* failure set is
a claim about what the diagnostic emitted, not about what compiles. A halting
diagnostic later in a unit never reaches the detail file at all, so "two errors"
and "two fixes from compiling" are different statements — and the zero-yield rows
above are consistent with that being true of some units here.

## SCORING A WALL BY THIS CENSUS WILL REPORT A WORKING FIX AS A NULL RESULT

**Measured 2026-09-16 (franks-ee), and it lands on the section above.** Three arms
over all 207 units:

| arm | compiler | cpuinfo walls | units OK | total errors |
| --- | --- | --- | --- | --- |
| base | pre-fix | both present | 21 | 396 |
| fix | post-fix | TDoubleRec only | 21 | 396 |
| stub | pre-fix | both stubbed out | 21 | 256 |

**`base` and `fix` are identical unit-by-unit, identical by count, and identical in
the first-error histogram — and the fix WORKED.** All 138 units traded the array
wall for a different error in the same slot, so the count held at 2 and the first
error stayed `TDoubleRec`:

```
aasmbase pre-fix : :36 TDoubleRec  /  :281 too many array initializer elements
aasmbase post-fix: :36 TDoubleRec  /  :35  an object type cannot have a constructor
```

**AN ERROR COUNT IS NOT AN ERROR IDENTITY.** `PXX_CORPUS_DETAIL`'s summary reports
counts and first errors, so scoring a wall with them alone reports a landed fix as
nothing. **Diff the detail files unit-by-unit, on the error TEXT**, not on `errs=N`
and not on the histogram. Same family as CLAUDE.md's line-31 finding: the
instrument is honest and is answering a narrower question than the reader supplies.

## SEVENTH NULL ROW — and the third wall is NOT in cpuinfo.pas

**Stubbing BOTH walls out of a copy of `cpuinfo.pas` moved units-compiling by ZERO**
(21 -> 21). The prediction that a third wall would swallow the population was right;
the prediction that it would be in the same file was **wrong — `cpuinfo.pas` compiles
clean with both stubbed.** The 138 land one file further on, at `an object type
cannot have a constructor`, which goes **18 -> 156 of 207** and is now the largest
single wall this corpus has recorded.

**That distinction is the whole value of the measurement**: "another wall in
cpuinfo" means keep grinding one file; "one shared wall one file on" means the next
lever is `feature-p-legacy-value-object-types` / `bug-p-object-value-types-standard-meaning`.
Ranking caveat fully intact — 156 is units QUEUED, and this umbrella has now
converted seven walls at a yield of zero.

**STUB BEFORE YOU FIX.** It answered the size question for almost nothing and
BEFORE the work, and it is the only reason we know the next wall is elsewhere.

---

## 2026-09-16 (frankS, later) — the wall ORDER matters, and I got it wrong before measuring

`fa397c761` fixes `var s: string = <named const>` (`globals.pas:502`). **It
changes nothing here today**, and the reason is worth more than the fix.

**I claimed this wall gated 138 units and was the cheaper lever than the object
wall. It does not, and it is not in front of it.** `globals.pas:502` sits
**BEHIND** the object-constructor wall: those units stop at the object
constructor and never reach the var initialiser. Measured on the real tree,
before and after:

| | units OK | total errors | first-error histogram | unit-by-unit |
| --- | --- | --- | --- | --- |
| before `fa397c761` | 21 | 396 | unchanged | identical |
| after | 21 | 396 | unchanged | identical |

**It only appeared to be in front because I found it with the object wall
STUBBED OUT.** The stub was there to reveal what was behind; I then read its
output as an ordering over the unstubbed corpus. A stub tells you what is
BEHIND a wall — it cannot tell you a wall is in FRONT of one, because in the
stubbed world that wall does not exist. **The stub answers "what is next", and
I read it as "what is first".**

That is the same family as the count-versus-identity finding above and it
arrives from the other side: there, an instrument that could not see a real
change; here, an instrument that showed a real change in a world I had built.
Both are honest and both are about a narrower question than the reader supplies.

**What the fix does deliver, measured where it is reachable** (stubbed tree,
cpuinfo ×2 + versioncmp's ctor):

- all 138 move from `not a constant` to **`unknown type: TSystemTime`**
- units compiling **22 → 22**

**Wall six is `TSystemTime` — an RTL type gap, same family as `TDoubleRec`,
Track B.** With that, the walls this umbrella has hit now alternate between
Track P parser gaps and Track B RTL type coverage:

```
1  TDoubleRec                  RTL type      (B, ticketed)
2  array-of-set var init       parser        (P, FIXED 14df2066b)
3  object constructor          language      (DECIDED against; see decide-old-style-object-types)
4  var = named string const    parser        (P, FIXED fa397c761)
5  TSystemTime                 RTL type      (B, unticketed)
```

**So the binding constraint is not one subsystem.** Two of the five are RTL
types we simply do not declare, and neither needs a compiler change or a
decision — which makes them the cheapest remaining lever, and the first
structural read this umbrella has had that is not "one more wall in one more
file".

**Ninth null row.** Five walls cleared or stubbed across the day, units
compiling 21 → 22. The standing caveat holds and has now been demonstrated
twice in one session: a wall's population is a queue position, the arms are
pxx-only (read deltas, not the absolute 21), and **an error count is not an
error identity** — `fa397c761` is invisible in every summary quantity and is
still a real fix.

## A STUB ORDERS THE STUBBED WORLD ONLY — it says what is BEHIND a wall, never that a wall is in FRONT

**Measured 2026-09-16 (franks-ee), correcting itself, and it corrects the advice in the
section above.** "Stub before you fix" is right and it is what found walls 4 and 5 at
all. What it does NOT do was never stated: **in the stubbed world the stubbed wall does
not exist, so the ordering you read off it cannot tell you that wall sits in FRONT of
what you found.**

`globals.pas:502` was found with the object wall stubbed and reported as gating 138
units and as the cheaper lever. **It gates nothing on the real corpus** — those 138 stop
at the object constructor and never reach the var initialiser. Before and after on the
unstubbed tree: 21 units OK, 396 total errors, identical unit-by-unit AND by error
identity.

**The discipline, with the missing line: stub to find the next wall, then RE-RUN
UNSTUBBED before claiming an ordering.** One command.

**Pair this with the count-vs-identity section above — they are the same family in
opposite directions, twelve hours apart.** There the instrument could not see a real
change; here it showed a real change in a world the measurer had built. Both honest,
both answering something narrower than the reader supplied.

**And `fa397c761` is the count-vs-identity rule biting a SECOND time**: a real fix,
invisible in every summary quantity — same units, same counts, same first-error
histogram. Two independent instances now, not one.

## THE FIVE WALLS, and the first structural read that is not "one more wall in one more file"

| # | wall | kind | state |
| --- | --- | --- | --- |
| 1 | `TDoubleRec` | RTL type | Track B, ticketed |
| 2 | array-of-set `var` init | parser | **FIXED** `14df2066b` |
| 3 | `object` constructor | language | **DECIDED AGAINST** (`decide-old-style-object-types`, option A) |
| 4 | `var` = named string const | parser | **FIXED** `fa397c761` |
| 5 | `TSystemTime` | RTL type | **FIXED** `c52d5b31b` (franks-ee) |
| 6 | `sizeof(files[0])` on a pointer-indexed element (`finput.pas:544`) | parser | **FIXED** `a931bef4d` (franks-ee) |
| 7 | parameterless call spelled WITHOUT parens when the name is OVERLOADED (`comphook.pas:386`) | parser | **OPEN — the head**, Track P, franks-ee |

**Two of the five are RTL types we simply do not declare** — no compiler change, no
decision, nothing to reverse. That makes them the cheapest remaining lever by some
distance, and it is the first time this umbrella's blockers have sorted into kinds
rather than into files.

**Wall 3 is the one to understand before ranking anything:** it is decided AGAINST, so
walls 4 and 5 sit behind a wall nobody is authorised to remove. **Do not rank 1 or 5 on
the 138** — that count comes from the stubbed world. **Nine null rows in a row**; the
yield of walls 1 and 5 stays unknown until wall 3 moves, and moving wall 3 requires a
decision recorded below the existing one.

## WALL 5 IS FIXED AND IT IS THE FIRST ONE THAT IS LIVE WITHOUT A PIN — rank RTL walls above compiler walls for that reason alone

**Landed 2026-09-16 by franks-ee, `c52d5b31b`: `SysUtils.TSystemTime`, `GetLocalTime`,
`DateTimeToSystemTime`, `SystemTimeToDateTime`.** Wall 5 of the five-wall table above is
cleared. The new head is `finput.pas:544` — `ReallocMem(files,afiles*sizeof(files[0]))`,
`sizeof` of an element reached by INDEXING A POINTER. That is a **parse** gap, not a type
gap, so it is Track P and it does not join the two RTL rows.

**The property that makes the kind-sort in the table ACTIONABLE, and it was not stated
when the table was written.** A wall's kind said what it would COST to fix. It also says
when the fix becomes REAL, and the two RTL rows differ from every other row on that axis:

- A **compiler** fix (walls 2 and 4, and anything in `compiler/**`) is **inert until the
  next pin.** `$(PXX_STABLE)` consumers keep the old behaviour until Track A pins.
- An **RTL** fix is **live the moment it lands.** Verified here, independently of the
  author's report: pin v410's directory contains no RTL at all (`builtin` and the binary,
  no `sysutils`), `TSystemTime` enters the tree in exactly one commit — `c52d5b31b`, not an
  ancestor of the pin — and the **pinned v410 binary compiles and runs a program using
  `TSystemTime`, `DateTimeToSystemTime` and `SystemTimeToDateTime`**, answering
  `1899 12 30` for `TDateTime(0.0)` and round-tripping to `0.0000`. The pin snapshots the
  compiler and its builtin units; `lib/rtl` is read from the tree.

**So "cheapest lever" understated it.** An RTL wall costs no compiler change, no decision,
AND no pin — it is the only class of umbrella blocker whose fix is worth something to
every other seat on the same day. Wall 1 (`TDoubleRec`) is the remaining member and should
be ranked accordingly.

**What this does NOT do is move the yield question.** Walls 4, 5 and 6 still sit behind
wall 3, which is decided against, so nine null rows in a row remain nine. Live-without-a-pin
is an argument about WHEN a fix pays, never about WHETHER this umbrella's count moves.

**Two conventions franks-ee read out of FPC's source rather than guessing, recorded so
nobody re-derives them:** `TSystemTime.DayOfWeek` is 0-based where `SysUtils.DayOfWeek`
is 1-based (a fixture must assert the DIFFERENCE, or it passes under either convention);
and `SystemTimeToDateTime` composes with a sign-correct `ComposeDateTime`, not by adding
— 1899-12-29 06:00 is -1.25 composed and -0.75 added. `GetLocalTime` returns UTC
deliberately.

**No ticket, and that is correct.** CLAUDE.md: filing instead of fixing is the error. The
table above is the bookkeeping.

## WALL 6 FIXED, AND ITS CENSUS IS THE SIXTH NULL ROW — PREDICTED AS ZERO IN ADVANCE, FOR THE SIXTH TIME

**`a931bef4d` (franks-ee): a `FindSym` MISS kept `SizeOf` on the name path, which cannot
index.** `SizeOf(<field>[index])` is accepted; 33/33 on the extended fixture, with a control
that can fail — pin v410 and a purpose-built pre-fix binary both refuse it with
`expected ')' before '['`, and `TR` is 12 bytes in that fixture so a pointer-width answer
cannot pass for a correct one.

**Four-arm census, against an expectation written down BEFORE the arms ran:**

| arm | result |
| --- | --- |
| stubbed | 105 units first-failed at the sizeof wall; afterwards **zero** detail files name `expected ')' before '['` anywhere. Cleared, not moved. Units-OK 22 → 22. |
| unstubbed | not one row changed. 21 → 21. No unit lost in either pair, compared unit by unit. |

**The unstubbed null is the half that carries the ordering claim, and it is the discipline
this umbrella wrote for itself working:** `finput` sits BEHIND the cpuinfo and versioncmp
walls on the real corpus, so the fix is worth nothing today and worth the whole 105 the
moment those clear. **Sixth null row, predicted as zero in advance for the sixth time** —
which is the only thing that makes a null row information.

**The absence instrument is the right one here.** "Zero detail files name the error string
anywhere" cannot be produced by accident; a units-OK count can. Cleared rather than moved is
a claim about error IDENTITY, not about a count, and this umbrella has been burned by the
difference before.

## WALL 7 — a one-cell defect, and this seat FAILED TO REPRODUCE IT (which refutes nothing)

**`comphook.pas:386`, `system.str(getrealtime-starttime:0:3,hs2)`.** franks-ee read the site
off the detail file's own `in:` line rather than inferring it — necessary, because the
diagnostic prints **no file name** and the symbol leads a reader to `globals.pas:386`, which
is a comment. (Verified here: it is `{ contains tpackageentry entries }`.) That is CLAUDE.md's
same-line-number rule paying for itself a second time in this umbrella.

Its reduction, eleven lines, with the two controls that make it one cell:

| | shape | verdict |
| --- | --- | --- |
| A | overloaded, bare | REFUSED `undefined variable (grt)` |
| B | overloaded, empty parens | COMPILES |
| C | overloaded, bare, plain RHS | REFUSED |
| D | the parameterful overload | COMPILES |
| E | **control** — NOT overloaded, bare | COMPILES |
| F | **control** — NOT overloaded, parens | COMPILES |

**So only the intersection fails:** a parameterless call spelled without parentheses when the
name is overloaded. Same shape as wall 6 — a door wired for one spelling of a reference and
not the other, and **the passing spelling is the one everybody writes in a test.**

**THIS SEAT COULD NOT REPRODUCE IT AND THAT IS A FACT ABOUT THIS SEAT'S FIXTURE.** Six
reconstructed rows plus four more in the real site's `str(...:0:3, s)` shape ALL COMPILE at
`a931bef4d`. **The reconstruction is worthless as a refutation, and the control says why: it
compiles under PIN v410 too** — a binary that predates both walls. A fixture that passes on
every compiler ever built cannot distinguish a fixed defect from one that was never there,
which is this file's own "if the machinery did nothing at all, would this row still pass?"
answering yes. **Recorded so nobody reads it as a contradiction of franks-ee's table**; the
difference is in something the reconstruction did not copy, and the fixture to trust is the
one with the failing rows in it. Asked for its eleven lines rather than guessing further.

**The method note franks-ee volunteered is the one to keep:** its FIRST run of that table
reported all six rows REFUSED, controls included, because the harness broke on spaces in a
tag and it was reading *"no error line printed"* as success. **The controls caught it** —
E and F are not decoration, they are what separates a finding from an instrument. It nearly
shipped a table in which the instrument was the finding, and said so unprompted.
