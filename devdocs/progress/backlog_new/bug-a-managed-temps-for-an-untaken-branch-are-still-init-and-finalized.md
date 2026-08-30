---
track: A
prio: 65
type: bug
blocked-by: []
status: new
owner: ""
found: 2026-08-30
found-by: frank-optimize, profiling bug-o-uforth-blocktest-runs-slower-under-pxx-than-under-cpython
summary: "A routine that merely MENTIONS a managed type in a branch it does not take pays that branch's temp init and finalization on every call. Measured in isolation at 44x: two functions with identical semantics and the same never-taken branch cost 0.294s and 13.060s for 20M calls. promocore.pas:796 documented this in 2026 and worked around it by hand-splitting three routines; eleven siblings kept the cost until 0c3ad8a10. The workaround does not scale and the codegen fix helps every program."
---

# Managed temps for an untaken branch are still init'd and finalized

## The isolated repro

Two functions, same semantics, same never-taken branch. The only difference is
whether the record type is named in the hot body or behind a call.

```pascal
type TBig = record neg: Boolean; limbs: array of Int64; end;

function SlowSplit(x, y: Int64): Int64;
begin SlowSplit := BTo(BAdd(BFromInt(x), BFromInt(y))); end;

function AddSplit(x, y: Int64): Int64;            { hot body names no TBig }
var r: Int64;
begin
  r := x + y;
  if ((x >= 0) = (y >= 0)) and ((r >= 0) <> (x >= 0)) then
    AddSplit := SlowSplit(x, y)
  else AddSplit := r;
end;

function AddInline(x, y: Int64): Int64;           { same, TBig named inline }
var r: Int64;
begin
  r := x + y;
  if ((x >= 0) = (y >= 0)) and ((r >= 0) <> (x >= 0)) then
    AddInline := BTo(BAdd(BFromInt(x), BFromInt(y)))
  else AddInline := r;
end;
```

20M calls each, `-O2`, x86-64, sha `0604b414089f`, box load 1.58 → 1.84 across
both halves:

| form | time | per call |
| --- | ---: | ---: |
| split — hot body free of `TBig` | **0.294 s** | 14.7 ns |
| inline — `TBig` named in the body | **13.060 s** | 653.0 ns |

**44x.** The branch is never taken in either. Full repro:
`$SCRATCH/uf/tbig.pas` shape above; it needs no RTL beyond a dynamic array.

## What the emitted code does

`PXXPromoAdd`'s prologue before `0c3ad8a10`, from `objdump` of a `-g` build:

```
sub    $0x160,%rsp                 <- 352-byte frame for a 3-pointer routine
lea    -0x48(%rbp),%rdi ; xor %rax,%rax ; mov $0x10,%rcx ; rep stos %al,(%rdi)
lea    -0x58(%rbp),%rdi ; ...                                    (x21)
```

Two problems, and they are separable:

1. **21 managed temps are zeroed unconditionally**, for branches that the
   inline-tier fast path exits before reaching. The epilogue finalizes them
   again — 30 calls in the first 400 instructions.
2. **A 16-byte clear is emitted as `rep stosb`** (`rcx=0x10`, `stos %al`), i.e.
   byte at a time with microcode startup, where two `mov %rax` would do. This is
   worth fixing on its own and is much the smaller change.

## Why it matters beyond one file

`promocore.pas:796` has carried the diagnosis since the feature landed:

> A function that so much as mentions a TBig pays managed prologue/epilogue on
> EVERY call [...] Measured: with the slow path inline, one PXXPromoAddInt cost
> ~344 ns; split out, the fast path is a handful of instructions. **Keep every
> hot routine free of TBig.**

That is a correct diagnosis and a **workaround**: it was applied to
`PXXPromoAddInt`/`SubInt`/`MulInt` and to nothing else, so eleven sibling entry
points kept paying it for the entire life of the feature — `PXXPromoCmp`, the
one every Python `<` goes through, at 303 ns per call. `0c3ad8a10` hand-split
four more. `Mod`/`And`/`Or`/`Xor`/`Shl`/`Shr`/`ToStr`/`ToVariant` still have it.

This is the `normalise-dont-special-case` shape exactly: a rule that every
future author must remember, enforced by nothing, silently costing 20-40x when
forgotten. The codegen fix removes the rule.

## Suggested work

**Sink managed-temp init and finalization into the branch that uses them**, or
equivalently do not materialise a temp in a block the flow does not enter.
Fallback if that is too large: emit 16-byte clears as two stores rather than
`rep stosb`, which is independent and helps every managed frame.

Then delete the hand-splits in `promocore.pas` and re-measure — if the codegen
fix is real, `AddInline` and `AddSplit` converge and the `*Slow` routines become
unnecessary rather than mandatory.

## Gate

`make compiler/pascal26` (the fixedpoint) plus `gate.sh quick`. This changes
prologue emission for every managed frame in every program, so it is a change
that wants Track T's full sweep against its sha before anyone leans on it, and
it should not be pinned the same day it lands.

## Not to be confused with

`0c3ad8a10` fixed the *instances* in `promocore.pas`. This ticket is the
*mechanism*, and closing it is what makes the next instance impossible rather
than merely absent.

## Raised p55 -> p65 (coordinator, 2026-08-30)

On frank-optimize's evidence, and on the count rather than the size of any one
win. **`promocore.pas:796` — "keep every hot routine free of the managed type" —
was violated three separate times in one day**, and frank-optimize fixed two of
them:

- the promotable-int hot paths carrying `TBig` (`e583ad825`);
- `PyVarSlotSet`'s unconditional `s := ''` on every variant slot copy including
  the integer path — a real 25-byte allocation under NilPy, because
  `PXX_NILPY_STR` deliberately makes a zero-length string real, so **the same line
  is free in Pascal and costs an allocation here**;
- and this ticket's own case, managed temps for a branch that is never taken.

frank-optimize's summary is the argument: *"that rule is enforced by nothing and
is forgotten silently at 20-40x."* An isolated repro on this one measured **44x**
— 20M calls, 0.294s against 13.060s, identical semantics, same never-taken
branch.

**Three independent violations in a day of a rule nothing enforces makes this a
root cause rather than a perf item.** It is the ticket that retires the rule by
making it unnecessary, which is worth more than any single site it fixes — the
tickets-closed-per-change measure `root-cause-over-microfix` asks for.
