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
blocked-by: [feature-p-legacy-value-object-types, bug-p-a-conditional-directive-cannot-read-a-const-whose-value-is-not-an-integer-literal, bug-p-a-conditional-directive-cannot-evaluate-in-over-a-set-constant, feature-p-unaligned-is-a-transparent-lvalue-not-a-function, bug-p-a-semantic-diagnostic-in-a-used-unit-names-no-file-at-all, bug-p-a-method-parameter-typed-through-a-forward-pointer-alias-never-matches-its-own-body, feature-p-the-element-count-form-of-initialize-and-finalize, bug-p-a-set-valued-record-field-cannot-be-written-in-a-record-constant, feature-b-sysutils-has-no-executeprocess-and-no-texecuteflags, feature-b-rtl-has-no-tdoublerec, feature-b-rtl-has-no-termio-unit-and-no-isatty]
summary: "Owner-set direction 2026-09-09: 'we are going to be more application driven, not just hunting down theoretical bugs but just.. let's get stuff rolling. so, we had practical targets like busybox. or compiling FPC itself.' NO TICKET FOR THIS EXISTED ANYWHERE IN devdocs/progress -- measured, zero hits. FPC's own compiler is ~400k lines of Object Pascal written by people who were not testing us, which makes it the largest and least self-serving Pascal corpus available, and it is the application-driven form of exactly what Track P has been doing by hand: every bug the P seats hunted from the backlog tonight would have been found by this target, in the order that actually matters. BLOCKED-BY IS GROWN BY ATTEMPTING, NEVER BY TRIAGE -- CLAUDE.md: 'Each failure names a ticket in the order it actually matters. What the attempt never touches was not blocking real-world usage.' STATE at 4c7c88d36 (attempt 7, probe #12): 20 of 207 units compile under both fpc and pxx, 10 are ORACLE-NO and can never be evidence about us, 177 fail. THE FOUR CONSECUTIVE NULL ROWS ENDED AND THEY ENDED CHEAPLY: cclasses.pas compiles, and the per-unit join says the +3 is exactly that unit plus its two direct dependents (crefs, rabase) -- so clearing the wall 150 units were stacked on was worth THREE, which is this umbrella's own queue-position finding confirmed rather than refuted. It took two bugs, both found by converting one halting diagnostic to ErrorRecover so a unit reports EVERY failure instead of the first: a method parameter typed through a forward pointer alias never matching its own body (ee560d0ad), and the element-count form of Initialize/Finalize (d095cb08d), which had been a DELIBERATE refusal. SEVEN walls cleared now; BOTH-OK has gone 9 -> 15 -> 15 -> 15 -> 15 -> 18. THE TExecuteFlags WALL IS CLEARED (2026-09-11, frankH): sysutils gained ExecuteProcess and TExecuteFlags, and cfileutl.pas:136 no longer stops anyone. It bought ZERO units -- a FIFTH null row -- and an A/B on ONE binary shows why: cfileutl, rgobj and aasmbase were all stopped at that SAME LINE, and they now stop at `unknown type: TDoubleRec` (x86_64/cpuinfo.pas:36) and `undefined variable (IsATTY)` (comptty.pas:66) respectively, the latter again ONE line reached by two units. BOTH NEW WALLS ARE NOW SETTLED TOO, SAME EVENING, AND BOTH LANDED ON THE UNIT CYCLE. termio.IsATTY was added (d57a1efaa) and rgobj+aasmbase moved to `comphook.pas:251 undefined variable (V_Status)`. I recorded that as the unit cycle, then CORRECTED myself to 'not the unit cycle, that ticket is done and its minimal shape passes' -- AND THE CORRECTION WAS ALSO WRONG. It IS the unit cycle, in an ORDER-DEPENDENT shape the fixed ticket's fixture structurally cannot express: CycleWaitUnit is a global and ParseUnitImplSection re-enters itself, so a unit named AFTER the cycle-closer in the same clause cleared the pending park. Both of my claims measured a real shape and generalised it to the bug; the quantifier was the invention each time. FIXED 2026-09-11, same evening, and the V_Status wall is CLEARED. TDoubleRec was NOT built: measured instead, and it buys zero, because cfileutl's implementation uses Comphook+Globals and `globals` alone already fails at that same V_Status; it was re-laned P and repriced 40->25 blocked-by the cycle. So THREE walls cleared or priced in one evening delivered every unit involved into ONE new wall -- which was then cleared too, the same evening, as the order-dependent residual of the unit cycle. globals, rgobj, aasmbase, comphook and cfileutl ALL now reach `unknown type: TDoubleRec` (x86_64/cpuinfo.pas:36), which is feature-b-rtl-has-no-tdoublerec, already in blocked-by and already repriced. MEASURED, AND THE SIXTH NULL ROW IS CONFIRMED -- A/B over all 207 units on TWO BINARIES differing by exactly 401c00f2b: BOTH-OK 21 before and 21 after, ZERO units newly compiling, ZERO regressed, and 101 of 207 units changed their first error -- ALL 101 from `undefined variable (V_Status)` and ALL 101 to `unknown type: TDoubleRec`. One wall into one wall, nothing scattered, half the corpus moved and the conversion rate was zero. TDoubleRec is now the first failure of 132 of 207 (64%). That is the largest single-wall transfer this umbrella has recorded and it is the cleanest possible statement of the queue-position finding: a wall's population counts units QUEUED behind it, never work. A SIXTH NULL ROW IS THE DEFAULT EXPECTATION FOR THE NEXT RE-RUN AND IT IS STATED HERE BEFORE THE RUN, not after: five walls in a row have converted at 0, 3 and 2 units, and every unit this one freed landed on the same next wall, which is the signature of a queue rather than a population. AND THE INSTRUMENT THIS UMBRELLA SAYS NOBODY BUILT ALREADY EXISTS: the compiler recovers up to MAX_REPORTED_ERRORS=20 semantic errors per unit, and tools/fpc_compiler_corpus_probe.sh pipes it through `head -1`. Taking that off shows the wall BEHIND the first one for free -- behind cfileutl's TDoubleRec sits `too many array initializer elements` at cpuinfo.pas:281 -- so the every-failure-per-subject census this umbrella has wanted for five null rows is a harness change, not a compiler feature. DO NOT RANK ANY OF THEM ON UNIT COUNT: attempt 7 measured the conversion rate of a cleared wall at three units. A second row went the same evening -- a set-valued record field (138604b5e), which is how tokens.pas writes its ~400-row token table -- and probe #12 says it bought TWO (tokens, rescmn) while eight more moved up to the TExecuteFlags wall. THREE WALLS, THREE JOINS, YIELDS OF 3 AND 2: a wall's population says how many units are QUEUED behind it, and the units that turn BOTH-OK are the ones for which it was the LAST wall. Near-disjoint sets; only the second is worth a number."
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
