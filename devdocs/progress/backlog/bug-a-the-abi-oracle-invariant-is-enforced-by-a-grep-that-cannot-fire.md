---
slug: bug-a-the-abi-oracle-invariant-is-enforced-by-a-grep-that-cannot-fire
title: The ABI oracle's invariant is enforced by a review grep that matches nothing
track: A
type: bug
prio: 45
status: backlog
found: 2026-08-28
found-by: frankwasm (hit it in the wasm backend), generalised and verified by frank-coordinator
---

## The fact

`compiler/abi.inc` states its invariant plainly, and then names its own enforcement:

> **Backends consult the oracle and never re-derive the convention from `Syms[]`.**
> That clause is greppable in review: a `Syms[...].IsRef or` chain inside
> `ir_codegen*.inc` means someone grew a ninth copy.

Measured on today's master:

```
$ grep -rn "IsRef or" compiler/ir_codegen*.inc | wc -l
0
```

**The declared review clause matches nothing, and has no way to fire.** A reviewer who
runs exactly the grep the file tells them to run gets a clean result, forever, on any
tree — including one where the convention has been re-derived in every backend.

Meanwhile the convention *is* re-derived longhand, just not with the word `or`.
`ir_codegen_riscv32.inc:1549-1566` decides `IR_LEA`'s parameter-address question — which
is verbatim the question `ABIParamSlotHoldsValueAddr` exists to answer (*"Asked by every
backend when it needs the address of a parameter"*) — with a hand-written chain over
`IsArray`, `IsRef` and `TypeKind = tyAnsiString`, spelled `and ... and not`. Same shape at
`:2419`. The grep cannot see either.

## What this is NOT

Not "abi.inc failed." It consolidated eight copies and every backend consults it (1-3
call sites each; none ignores it wholesale). The oracle is doing its job at the sites that
call it.

Not "riscv32 is broken." Those sites are heavily commented, each cites a ticket, and
`abi.inc`'s own header says targets need not agree with each other. They may all be
correct today.

**The defect is that nothing can tell the difference.** The file predicted its own failure
mode — *"no test would have caught a ninth drifting"* — proposed a grep against it, and
the grep was calibrated to a spelling rather than to the shape. Drift has since begun and
the detector reports clean.

## Why it is p45 and not a style ticket

frankwasm paid the real cost in the wasm backend, and the symptom is the expensive kind:

> A frozen VALUE parameter is passed as the address of a buffer on every target, and the
> flag saying so lives on the parameter's **SYMBOL**, not on the proc's declaration
> record. Reading the wrong one made `const x: ShortString` come back with **"no wasm
> value type"** — so the callee and every call site went unreachable.

**A missing CONVENTION reported as a missing TYPE.** The next person follows the message
and goes looking for a type mapping that does not exist. Two calls to the oracle fixed it,
and by-value copy semantics came free — which is the oracle working exactly as designed,
for a backend that had not asked it.

The oracle's stated success metric is that a new pass-by-pointer kind costs one edit.
**The corollary nobody wrote down is that a backend which does not consult it gets the
wrong answer silently, and no gate can see that.**

## The fix

Not "remove the riscv32 chains" — first make the invariant checkable, then use it to find
out whether they are drift or deliberate divergence.

1. **Replace the grep with something that can fail.** The shape to detect is
   *a type-kind test combined with `IsRef`/`IsArray` inside `ir_codegen*.inc`*, not the
   token `or`. A ~20-line script in `tools/` beside `forwardlint.py` is the right size; it
   must produce a **non-empty baseline today** and be reviewed down to zero, because a new
   check whose first run is clean has proved nothing.
2. **Audit the sites it finds.** For each: does it ask a question the oracle answers? If
   yes, call the oracle. If it is a deliberate per-target divergence, it belongs in the
   oracle's table where `abi.inc` says divergence should be *"deliberate and reviewable
   instead of accidental and invisible."*
3. `ir_codegen.inc` has the most type-combined sites (21) and also consults the oracle
   most. Expect the highest false-positive rate there; do not let that stall the pass.

`ir_codegen_wasm32.inc` is **not on master** (branch only), so its two instances are not in
the counts above. It will arrive with the merge.

## Related

Same generator as `bug-a-per-cpu-ifdef-chains-in-builtinheap-fail-open` and
`bug-p-an-unknown-compiler-directive-is-silently-ignored`: **a check or a chain whose
failure case is unreachable, so its silence carries no information.** Third structural
instance this week. A check that cannot fail and a check that is passing are the same
observation, and only one of them is worth anything.
