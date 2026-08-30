---
track: C
prio: 55
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
