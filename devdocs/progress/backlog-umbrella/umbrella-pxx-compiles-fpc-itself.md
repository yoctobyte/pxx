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
blocked-by: [feature-p-legacy-value-object-types, bug-p-a-conditional-directive-cannot-read-a-const-whose-value-is-not-an-integer-literal, feature-p-unaligned-is-a-transparent-lvalue-not-a-function]
summary: "Owner-set direction 2026-09-09: 'we are going to be more application driven, not just hunting down theoretical bugs but just.. let's get stuff rolling. so, we had practical targets like busybox. or compiling FPC itself.' NO TICKET FOR THIS EXISTED ANYWHERE IN devdocs/progress -- measured, zero hits. FPC's own compiler is ~400k lines of Object Pascal written by people who were not testing us, which makes it the largest and least self-serving Pascal corpus available, and it is the application-driven form of exactly what Track P has been doing by hand: every bug the P seats hunted from the backlog tonight would have been found by this target, in the order that actually matters. BLOCKED-BY IS GROWN BY ATTEMPTING, NEVER BY TRIAGE -- CLAUDE.md: 'Each failure names a ticket in the order it actually matters. What the attempt never touches was not blocking real-world usage.' STATE at dbb96cdb6 (attempt 5, probe #9): 15 of 207 units compile under both fpc and pxx, 10 are ORACLE-NO and can never be evidence about us, 182 fail. 150 of the 182 stop on ONE call site, `unaligned` at cclasses.pas:1327. FIVE walls have been cleared (unit cycle 158 units, bitsizeof 163, PSizeUInt 150, IndexQWord 96, and the conditional-directive family) and BOTH-OK has gone 9 -> 15 -> 15 -> 15: bitsizeof bought all six and the three largest bought none. THE WALLS ARE STACKED IN ONE SHARED UNIT, so a blocker's unit count is a QUEUE POSITION, not a size, and this umbrella must not be ranked on it."
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
