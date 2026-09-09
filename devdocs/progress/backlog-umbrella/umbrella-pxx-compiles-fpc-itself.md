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
blocked-by: [bug-p-a-unit-cycle-closed-through-an-implementation-uses-cannot-see-the-other-interface, bug-p-a-conditional-directive-cannot-read-a-constant-or-a-type-the-source-declares, feature-p-legacy-value-object-types]
summary: "Owner-set direction 2026-09-09: 'we are going to be more application driven, not just hunting down theoretical bugs but just.. let's get stuff rolling. so, we had practical targets like busybox. or compiling FPC itself.' NO TICKET FOR THIS EXISTED ANYWHERE IN devdocs/progress -- measured, zero hits. FPC's own compiler is ~400k lines of Object Pascal written by people who were not testing us, which makes it the largest and least self-serving Pascal corpus available, and it is the application-driven form of exactly what Track P has been doing by hand: every bug the P seats hunted from the backlog tonight would have been found by this target, in the order that actually matters. BLOCKED-BY IS EMPTY ON PURPOSE AND MUST BE GROWN BY ATTEMPTING, NOT BY TRIAGE -- CLAUDE.md: 'Each failure names a ticket in the order it actually matters. What the attempt never touches was not blocking real-world usage.'"
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
