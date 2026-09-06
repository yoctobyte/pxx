---
track: A
prio: 45
type: bug
status: backlog
owner: ""
created: 2026-09-06
found-by: frankA
tags: [cross-target, riscv32, aarch64, arm32, frontends, builtinheap]
blocked-by: []
summary: "FIXED FOR RUST AND ZIG, OPEN FOR THE CLASS. Some backends lower ordinary constructs onto routines that live in `builtinheap`, and a frontend driver cannot see it: riscv32 routes EVERY integer write through PXXWriteDecW, and the aggregate-result epilogue lowers onto PXXMemMove on aarch64/arm32/riscv32. A driver that does not pull the unit produces a working binary on the targets whose codegen happens to be inline and `compiler error: <routine> not found` -- an internal-fault-shaped diagnostic -- on the rest, for a program whose source mentions neither strings nor the heap. Measured: `fn main(){ println!(\"{}\", x); }` ran on x86-64/i386/aarch64/arm32 and failed on riscv32, while the SAME print from Pascal worked there, because a Pascal program pulls builtinheap ambiently. Rust and Zig now ask `TargetCodegenCallsHeapRuntime` (emit.inc). STILL OPEN: eparser pulls nothing and has the same hole; the predicate is a hand-maintained union of two known mechanisms; and its xtensa entry is taken from cparser.inc's comment rather than measured."
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
