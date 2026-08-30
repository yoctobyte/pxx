---
track: A+C
prio: 65
type: bug
status: new
blocked-by: []
owner: ""
summary: "On x86-64 a C function uses the C ABI (SysV); on aarch64 and arm32 it uses pxx's INTERNAL positional convention, because cparser.inc's per-target prologue spills disagree. So `is this proc reached by the C ABI?` has a different answer per target, nothing names that in one place, and the `and (not CProgramMode)` guards on the aarch64/arm32 call arms exist to compensate. Split out of refactor-a-collapse-the-c-frontend-sysv-prologue-copy, whose x86-64 half landed byte-identical; this half is an ABI CHANGE and needs a behavioural gate, not byte-identity."
---

# A C function's calling convention depends on which target it is built for

Split out of [[refactor-a-collapse-the-c-frontend-sysv-prologue-copy]] rather
than bundled into it. That ticket's x86-64 half was a **pure deletion** — the C
copy and the shared arm already agreed, and the collapse changed no emitted byte.
**This half cannot be**: it changes what convention a C function uses.

## The table

| target | cparser's prologue spill | so a C function is... |
| --- | --- | --- |
| x86-64 | collapsed onto `EmitParamSpillsForTarget` (SysV) | **C-ABI** |
| aarch64 | `cparser.inc:11193` — positional, *"mirrors the Pascal aarch64 spill"* | **internal** |
| arm32 | `cparser.inc:11143` — positional, word-based | **internal** |

Nothing states that in one place, so every call site that wants to know "is this
proc reached by the C ABI?" encodes the answer per target — and it is not the
same answer.

## What it has already cost

`bug-a-a-c-mode-function-took-the-cdecl-call-path-on-aarch64-and-arm32` — five
p70 NEW-REDs (four `test-c-conformance-aarch64` shards plus `test-lua-cross`).
`ProcExternal[p] or ProcCdecl[p]` is **correct on x86-64 and wrong on
aarch64/arm32**, purely because of the table. Three strikes on that one
predicate: `b362` (indirect, lua + sqlite), `eeb51710e` (aarch64 direct),
`6d2939f38` (arm32 direct).

The `and (not CProgramMode)` guards now on the aarch64 and arm32 call arms are
**compensating for this table**. They are correct, and they are a workaround:
they stop a C-mode callee being called by a convention its own prologue does not
implement.

## Why it is its own ticket, and what its gate must be

The parent's gate is byte-identity, and byte-identity is the wrong instrument
here — a correct fix **will** change emitted bytes on aarch64 and arm32, by
design. Bundling the two would have let each change's gate excuse the other:
the byte-identity result would be false and *expected* to be false, and the one
signal that says "you changed behaviour" would be pre-explained away. (Exactly
frankA's argument for landing its riscv32 convention fix separately from this
refactor, and it applies again one level down.)

So this ticket needs:

1. A **behavioural** gate — C conformance on aarch64/arm32 plus `test-lua-cross`,
   asserting the new convention, not the old bytes.
2. **Removal of the compensating `not CProgramMode` guards in the same change** —
   they describe something accidental; once the prologues agree they would be
   describing something real, which means they are no longer needed and leaving
   them in hides whether the fix worked.
3. A single place that answers "is this proc reached by the C ABI?", so strike
   four does not land on a fourth call site.

## Carry-in from frankA's riscv32 fix

Expect **at least one arm to be correct already**. frankA's fix was a *deleted
case, not an added one*: the conformant layout already existed as the variadic
tail reversal gated on `ProcVariadic`, because a `va_arg` walk reads forward from
overflow and so needed psABI order. The ordinary path was the wrong one. The win
is deleting the disagreeing cases, not synthesising another.

## Re-rated p55 -> p65 and re-laned C -> A+C (coordinator, 2026-08-30)

frankC measured the shape where **no compensating guard applies** — a Pascal unit
whose implementation is a C translation unit (`uses './abi.c'`), so a Pascal-mode
caller meets a bodied C callee and the two sides must already agree. Binary at
fixedpoint `a7a03ffb95e1`; probe and runner in `/tmp/frankC-share/abi-probe/`.

```
shape                       x86-64  aarch64  arm32  riscv32  i386
f(double x, int n)            ok     0.00     ok      ok     Nan
f(int n, double x)            ok      ok     0.00     ok     Nan
f(int,int,int) -> 123         ok      ok      ok      ok     321
f(double a, double b)         ok    27.50     ok      ok     Nan
f(int,double,int,double)      ok   1034.00 refused    ok     Nan
f(float f, int n)             ok     0.00     ok      ok     Nan
```

**This is a silent-wrong-answer bug, not a consistency refactor.** Ordinary Pascal
calling ordinary C returns wrong numbers on three of five targets. CLAUDE.md's
compat table: *"real Pascal source compiles but runs wrong → bug, own lane, own
prio"*. p55-as-a-follow-on-refactor understated it.

**Why 65 and not higher:** the affected shape is a Pascal unit implemented by a C
TU, which is not yet common in the tree, and the two targets that matter most for
the ESP campaign — riscv32 and x86-64 — are clean. **Why not lower:** wrong
values, no diagnostic, and `i386` shows it with **no float at all**.

- **i386 is a fourth affected target and the worst — 6/6 wrong**, and nobody had
  listed it. `cparser.inc:11085` has its own i386 arm; `ir_codegen386.inc` carries
  the same three guards. Its divergence is argument **order**, hence `321` for
  `123`.
- **riscv32 is clean on all six** — frankA's psABI convention fix, and this
  ticket's own "expect one arm to be correct already" landing as written.

## It is an A ticket with a C-side deletion, and that is why frankC stopped

The prologue is Track C's; the compensating guards are **seven sites across three
Track A backends** — `ir_codegen_aarch64.inc:2993,3188`,
`ir_codegen_arm32.inc:2658,2965`, `ir_codegen386.inc:3204,3561,3646` — and this
ticket's own gate requires them in the same commit.

**Deleting the `cparser.inc` arms alone is strictly worse than the status quo**: an
AAPCS prologue against still-positional C-mode call sites breaks every C-to-C call
on three targets in order to fix the bridge.

**The destination already exists.** `EmitParamSpillsForTarget` has proven
`ProcCdecl` arms for i386 / aarch64 / arm32 / x86-64, each mirrored from that
backend's external-call marshalling — a classification validated every time pxx
calls libc with a float. The aarch64 arm's own comment records that it was **not**
mirrored from `cparser.inc`, *"that one is POSITIONAL and says so."* So the C side
is the same three-arm deletion the x86-64 half already was.

## The gate the ticket names cannot prove this

A pure C program is self-consistent **both before and after** — positional on both
sides today, AAPCS on both sides after — so `test-c-conformance-*` and
`test-lua-cross` can detect a **regression** here but can never go red-to-green.
**The differentiating shape is the probe above, and it belongs in `test/` as the
behavioural gate.** Anyone who runs the cross suites, sees green, and concludes
the convention was asserted has measured the wrong thing.

## Two notes recorded so they are not re-chased

- **No cross-gcc on this box** (no `aarch64-linux-gnu-gcc`, no clang, x86-64 gcc
  only), so "prototype against real gcc" is not executable for the two targets in
  question. **It also was not needed**: unlike the bitfield case, where only gcc
  could say what `sizeof` should be, a calling convention's observable is a
  returned number and that number is target-independent arithmetic. `f(2.5, 4)` is
  `10.00` everywhere, so a disagreeing target is wrong **by construction**, with no
  oracle to consult. gcc pinned the x86-64 row only.
- **A non-finding:** an early run segfaulted on `mix4` on x86-64 *and* riscv32 —
  the two clean targets. Pascal `Mix4` and C `mix4` differ only in case, bind
  case-insensitively, and recurse until the stack dies. Renaming gives `1234.00`.
  Not a crash on the correct path.
