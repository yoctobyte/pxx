---
track: A
prio: 45
type: bug
status: working
owner: frankb-8e
created: 2026-09-06
found-by: frankA
tags: [cross-target, riscv32, aarch64, arm32, frontends, builtinheap]
blocked-by: []
summary: "FIXED FOR RUST, ZIG AND BASIC; OPEN FOR THE CLASS -- AND THE CLASS IS MUCH LARGER THAN THIS TICKET'S TABLE OF TWO. MECHANISM: any backend may lower an ordinary construct onto a routine that lives in `builtinheap`, and no frontend can see which, so a driver that does not pull the unit emits a working binary on the targets whose codegen happens to be inline and an internal-fault-shaped `compiler error: <routine> not found` on the rest -- for a program whose source mentions neither strings nor the heap. The guard is `TargetCodegenCallsHeapRuntime` (emit.inc), a HAND-MAINTAINED UNION that documents two routines (`PXXWriteDecW`, `PXXMemMove`). SIZE OF THE SURFACE, measured 2026-09-22 at e7e925193 and this is the ticket's central number now: ONE frontend's five committed .bas fixtures, built against pinned fda77c48b8ee, name FIVE different missing things (`PXXWriteCharW`, `PXXWriteNL`, `PXXWriteFrozen[B]W`, `PXXWriteDecW`, and the softfloat kernel `__pxx_l2d`); and a census over the five non-x86 backends counts 374 `FindProc('PXX...'|'__pxx...')` call sites, 276 of which raise `not found`, naming 71 DISTINCT ROUTINES -- a count of call sites is not a count of routines, so 71 is the figure to quote. SO EXTENDING THE LIST IS NOT THE FIX AND THE NEXT SEAT SHOULD NOT DO IT: the two entries are the corner of the surface that someone happened to trip over. RETIREMENT CONDITION, unchanged and now argued rather than asserted: the union stops being hand-maintained -- either every skeleton driver pulls unconditionally and the predicate is deleted, or the routine set is derived from the backend that emits it instead of restated beside it. A seat that appends a third routine has made the ticket harder to close. STILL OPEN: eparser pulls nothing and has the same hole; the predicate's xtensa entry is still inherited from cparser.inc's comment rather than measured."
---

# A frontend cannot see that a backend calls library routines

## The two mechanisms, with their measured target sets

| routine | who calls it | targets |
| --- | --- | --- |
| `PXXWriteDecW` | every ordinal write | **riscv32** only (`ir_codegen_riscv32.inc`, the `Is64BitRISCV32(tk) or TypeIsOrdinal(tk)` arm). i386 and arm32 reach it only for a WIDTH on a 64-bit value; x86-64 and aarch64 never. |
| `PXXMemMove` | the aggregate-result epilogue | **aarch64, arm32, riscv32** measured; `cparser.inc`'s hosted branch names xtensa for the same reason. |

**The sets OVERLAP without one containing the other, and that is the whole
lesson.** The first version of the predicate was called
`TargetWritePathNeedsHeapRuntime` and it was too narrow within the hour: with
only the write mechanism covered, `test_rust_option.rs` — a record return, no
printing at all — failed on aarch64 and arm32 while passing on i386 and
riscv32. **A guard named after the routine you have in hand answers correctly
for the case you have in hand.** It is now named for the question,
`TargetCodegenCallsHeapRuntime`, and the union is
aarch64/arm32/riscv32/xtensa.

## Why it was invisible until 2026-09-06

Both frontends refused every non-x86-64 target, and the refusal ran before a
compile could be attempted. It came out of the entry-stub extraction
(`bug-a-three-frontend-drivers-hand-write-an-x86-64-program-tail-and-a-target-refusal-is-what-hides-it`),
and one of its faces is worth carrying: **`test_zig_skeleton.zig` failing to
compile for riscv32 was written down as a Zig frontend defect, and it was this.
A per-target exclusion written from a failing compile records the target the
defect was VISIBLE on, not the target it is about.**

## Fixed for two frontends, and what is left

`rparser.inc` and `zparser.inc` now pull `builtinheap` + `builtin` when the
predicate says so (and `softfloat` first on riscv32/xtensa non-bare, mirroring
`cparser.inc`'s hosted branch — pulling the two units alone moved the error to
`the soft-float kernel __pxx_l2d is not linked` rather than clearing it, which
is measured and not predicted). Zig pulled **no** unit at all before this.

Residual, none of it fixed here:

1. **`eparser.inc` pulls nothing** — FIXED, along with the two defects in front
   of it; Erlang now matches its native output on all four cross targets.
   **But the census that closed it found SIX MORE DRIVERS in the same state**,
   see below.
2. **The predicate is a hand-maintained union.** A third mechanism, or a new
   backend that lowers a construct onto a library routine, will not announce
   itself here. What would retire this ticket is the backend DECLARING its
   library dependencies rather than a frontend guessing them.
3. **The xtensa entry is unexercised** — both frontends that ask still refuse
   xtensa, and the entry comes from `cparser.inc`'s comment, not from a run.

## Acceptance

`test-skeleton-frontends-cross-target` covers the fixed part: the same program
on every accepted target, compared whole against its own native run, no
expected text anywhere in the row. Positive control taken and RED — with the
Rust unit pull reverted, four rows report `does not COMPILE` and name the right
targets. **A compile failure is a failing row and not a skip in that recipe, on
purpose**: a skip would have recorded this defect as "not applicable".


## 2026-09-07 (frankA) — THE CENSUS: six more drivers, and one of them already crosses

Ran the adoption matrix the eparser finding implied — every frontend driver
against every shared per-target emitter — and then widened it to the frontends
nobody names. `compiler/` holds nine skeleton drivers, not three:

| driver | language | refuses non-x86-64 | hand-written x86-64 | pulls units |
| --- | --- | --- | --- | --- |
| `rparser` | Rust | narrowed to 5 | none left | yes |
| `zparser` | Zig | narrowed to 5 | none left | yes |
| `eparser` | Erlang | narrowed to 5 | none left | yes |
| `aparser` | Ada | **x86-64 only** | **none** | **no** |
| `fparser` | Fortran | **x86-64 only** | **none** | **no** |
| `gparser` | Algol | **x86-64 only** | **none** | **no** |
| `lparser` | LOLCODE | **x86-64 only** | **none** | **no** |
| `wparser` | Whitespace | **x86-64 only** | **none** | **no** |
| `bparser` | BASIC | **NO REFUSAL AT ALL** | **none** | **no** |

**BASIC is the control and it cost nothing to read**, because it has no refusal:
`test_basic_comprehensive.bas` is already IDENTICAL to its native output on
i386, aarch64 and arm32, and fails on riscv32 with
`the soft-float kernel __pxx_l2d is not linked` — this ticket's defect, exactly.

So two things follow, and the second is the one worth acting on:

1. **BASIC has crossed to three targets for some time and nothing measures it.**
   Not a defect; an unrecorded capability, which is how a capability gets lost.
2. **The five remaining refusals are probably stale.** None of those drivers
   hand-writes a byte of machine code — which was the whole reason the Rust,
   Zig and Erlang refusals were load-bearing — and their sibling with no refusal
   works. Probably, not certainly: unmeasured until each is run, and that is the
   ordering this group has already been burned by once.

**AND THE PULL BLOCK IS NOW ON ITS THIRD COPY, heading for its ninth.** Three
drivers carry the same six lines (softfloat, then builtinheap, then builtin,
guarded by `TargetCodegenCallsHeapRuntime`), and six more need it. Two is a
smell and three is a design flaw, so the next commit folds it into one shared
routine beside `EmitProgramPrologue` — which all nine already call — rather than
adding a fourth copy. **A minimal fix to a duplication bug adds a copy**, and
this ticket exists because a mechanism nobody could see from a frontend was
spelled out per frontend.


## 2026-09-18 (frankS) — THIRD MECHANISM, AND IT IS THE PASCAL DRIVER ITSELF

`read` / `readln` / `Eof` lower onto `PXXReadLine` / `PXXReadVar*` /
`PXXReadDiscard` / `PXXStdinEof`, and **nothing told the Pascal driver's own
need-detector that a `read` token implies builtinheap.** Under
`-uPXX_MANAGED_STRING` that broke readln on **all five cross targets plus
x86-64**, three different messages, one cause:

| target | message | since |
| --- | --- | --- |
| i386 / arm32 / aarch64 / riscv32 / xtensa | `PXXReadLine not found` | predates 2026-09-18; reproduces on the pin |
| x86-64, any target type | `PXXLineEnsure not found in builtin unit` | `0ab100740`, when its asm reader started sharing the builtin buffer |
| x86-64, frozen-string target | `call to a runtime stub that was never emitted` | reproduces on the pin |

Fixed in `295bcceb9` by adding the pull to `DetectPascalRuntimeNeeds`, with a
fixture (`test_readln_in_a_frozen_string_build.pas`, x86-64 and i386 rows) whose
positive control is the pinned compiler refusing it on both.

**This is not a fourth ticket because it is not a fourth mechanism — it is the
same one arriving in the driver that looked immune.** `DetectPascalRuntimeNeeds`
already carries two paragraphs saying, in those exact words, *the dependency was
moved and this is where it has to be paid* — once for floats, once for a frozen
string written with a field width. `read` is the third, and **why nobody paid it
is the better argument for this ticket's prio than any count of instances:**
x86-64 emitted its own self-contained reader, so the pull looked
cross-target-only, and the five targets that actually needed it were failing in
a build mode no row covers. A hand-maintained union of known mechanisms grows a
new member every time a construct is shimmed onto a helper, and the member is
invisible until someone compiles in the one mode that exercises it.

### A CROSS-TARGET CENSUS IS NOT A CROSS-BUILD-MODE CENSUS

The census that cleared the readln de-duplication ran eight fixtures across five
`--target=` flags and found fifteen shapes byte-identical. It was right about
agreement and **wrong about completeness**, and the reason is the axis it was
given: it varied TARGET and never varied BUILD MODE, so it compared two readers
on programs that BUILD — and there was an entire mode in which one of them does
not. `-uPXX_MANAGED_STRING` is not an exotic corner: **it is the model
`compiler.pas` itself is compiled with.** The population excluded the build the
compiler uses on itself.

This is the house rule with a new axis attached — a census answers honestly
about whatever it enumerates, and that applies to whoever drew the boundary, not
only to whoever ran it. **Wherever stdin, strings or the heap are involved, the
frozen-string model deserves a row**, because it is the one mode where the
managed-string runtime is absent and every dependency that was quietly riding on
it comes due.


## 2026-09-22 (frankb-8e) — BASIC fixed, and the size of the surface measured

**Landed `e7e925193`.** `bparser.inc` was the last skeleton driver with no
`PullTargetRuntimeUnits` call, so **every BASIC program that printed anything
refused on riscv32 and xtensa.** Four constructs x six targets before the fix:
a program with no `PRINT` built on all six; `PRINT` of a number and of a string
literal built on x86-64/i386/arm32/aarch64 and refused on the other two. After:
24/24 build, and riscv32's runtime output under qemu is byte-identical to the
x86-64 oracle on all four.

### Why the suite could not have caught it — the target list, not the fixtures

Five `.bas` fixtures ALREADY ran cross, over `i386 aarch64 arm32`, which is
**exactly the set of cross targets on which this defect does not reproduce.**
The list now reads `i386 aarch64 arm32 riscv32 xtensa` and both additions
**run** rather than merely building — `qemu-xtensa` executes a hosted `.bas`
today. Nothing about the fixtures needed to change.

### The number this ticket should be ranked on

| instrument | population | result |
| --- | --- | --- |
| five `.bas` fixtures vs pinned `fda77c48b8ee`, riscv32 | one frontend | **5** distinct missing routines |
| `FindProc('PXX…'\|'__pxx…')` census, five non-x86 backends | riscv32 83, arm32 56, aarch64 54, xtensa 36, wasm32 5 | **374 sites**, 276 erroring, **71 distinct routines** |
| this ticket's own table | — | **2** |

Tree for both: `e7e925193`. **Quote 71, not 374** — a count of call sites is not
a count of routines, and the two get confused precisely because 374 is the
bigger number.

The five from one frontend: `PXXWriteCharW`, `PXXWriteNL`,
`PXXWriteFrozen[B]W`, `PXXWriteDecW`, and the softfloat kernel `__pxx_l2d`.
**The residual on this ticket predicted exactly this** — *"a third mechanism, or
a new backend that lowers a construct onto a library routine, will not announce
itself here"* — and three arrived at once, from the frontend that happened to be
next.

### Position of the pull is load-bearing in TWO directions

Recorded because the shared routine's own header sends you to the first wall:

| placement | outcome |
| --- | --- |
| after `EmitExit` | `PXXWriteNL not found`, **unchanged**, from a binary that already had the fix. This is what `PullTargetRuntimeUnits`' header prescribes; that header was written from the CALL-STUB drivers. |
| after `ParseBBlock` | `invalid IR symbol reference in store_sym` on all four non-x86 targets — parsing a Pascal unit moves the symbol table under an AST already holding indices into it. `10 LET A = 1` trips it. |
| before the prescan | correct — no BASIC symbol allocated, no node built. |

`aparser.inc` and `gparser.inc` already carried a measured warning about the
first wall. **I hit it anyway, because I read the shared routine's header and
not the sibling call site.** That is this repo's own sibling rule failing in the
direction it usually fails: I grepped for the routine, not for the other
spelling's handler.

### Residual, for whoever takes the class

`eparser` still pulls nothing. The xtensa entry in the predicate is still
inherited from a comment. **And the thing that would retire this ticket is not
a bigger list** — it is removing the need for one. The cheapest honest version:
have every skeleton driver pull unconditionally and delete
`TargetCodegenCallsHeapRuntime`, paying the unit cost on x86-64 to buy the
whole class. That trade has NOT been measured and is the next thing to measure.
