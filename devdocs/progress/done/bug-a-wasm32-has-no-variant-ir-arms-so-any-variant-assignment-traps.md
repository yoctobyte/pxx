---
slug: bug-a-wasm32-has-no-variant-ir-arms-so-any-variant-assignment-traps
track: A
prio: 30
type: bug
status: done
blocked-by: []
owner: frankA
created: 2026-09-01
found-by: frankC (while fixing bug-a-managed-locals-leak-at-ORDINARY-scope-exit-on-wasm32-and-a-variant-local-traps)
summary: "FIXED (a52c1810e). wasm32 lowers Variant: IR_VAR_STORE, IR_VAR_BOX, IR_VAR_BINOP and -- a FOURTH arm this ticket does not name -- the WRITE path, which was a refusal hiding behind the store and became visible the moment the store lowered. Verified with the four cross-target variant tests the other 32-bit backends already use rather than a new one, all green against the native oracle and wired into test-wasm32. The scope-exit PXXVarClear arm this ticket calls written-and-unverified is now proven REACHED, from the artefact (wasm2wat shows the call in the epilogue), not from a survival loop. Ranked by measurement first: 222 of 278 wasm32 gap instances over 300 corpus sources were this op."
---

# wasm32 has no Variant IR arms, so any Variant assignment traps

## Measured

```
program v1;
var v: Variant;
begin
  WriteLn('before');
  v := 42;
  WriteLn('after int assign');
end.
```

`--target=wasm32 -Fulib/rtl/platform/wasi`, `wasmtime run` (48.0.1): exit 134,
`wasm trap: wasm 'unreachable' instruction executed`, and **`before` never
prints** — the whole body is replaced, not just the assignment.

Two controls, both run:

- the same program with the `v := 42` line removed prints `before` and exits 0,
  so declaring a Variant is fine and the harness works;
- a trivial `WriteLn` program prints and exits 0.

So the trap is the assignment, and it is at **program level** — no procedure, so
no frame, no scope-exit release, nothing this could share with the managed-local
leak it was found beside.

## The compiler already says why

`WasmUnsupported` does not print at the trap; it records a reason and the
backend lists every broken body at COMPILE time. That list says:

```
    main$0 — statement IR op 43
```

`defs.inc:910`: `IR_VAR_STORE = 43`. The report was there the whole time and the
first reading of this defect (a table row saying "Variant: trap, exit 134") came
from running it rather than from reading what the compiler had already printed.

## Scope

| op | wasm32 | riscv32 |
| --- | --- | --- |
| `IR_VAR_STORE` (43) | 0 | 2 |
| `IR_VAR_BINOP` (44) | 0 | 2 |
| `IR_VAR_BOX` (45) | 0 | 2 |

Three ops. Port from riscv32 or aarch64. The one wasm32-specific piece: any
Variant op needing the address of an RTTI blob must go through the
descriptor-cell indirection (`WasmRecDescAddr`, `ir_codegen_wasm32.inc`), because
this backend has no code→data fixups and emits every address inline as a
constant — the blob's offset does not exist while bodies are being emitted.

## Do not read the PXXVarClear arm as coverage

`74e33af46` gave wasm32's scope-exit release a Variant arm alongside the four
others it fixed. It is written to the same shape as every other backend's and it
has **never executed**, because no program can get a Variant into a local
without tripping the trap above. When this lands, that arm is the first thing to
measure — a `Variant` local holding a runtime-built string, 300 iterations,
`-dPXX_ALLOC_CENSUS`, against x86-64.

## Ranked by measurement, 2026-09-03 (frankA)

300 sources from the test corpus compiled for wasm32 with the fixed coverage
report (52d134518, the first build that can name more than one gap per body):
**222 of 278 gap instances are `statement IR op 43`, this ticket.** The next
one down is 18. Variant is not one of several wasm32 gaps; it is four fifths of
them, and every other refusal in the corpus put together is under a quarter of
its count.

Wired under `umbrella-wasm-is-a-real-platform` on that evidence -- grown by
attempting the target rather than by triaging the backlog. The census is a
FLOOR (a body stops at its first refusal), which can only understate the tail,
never this head.

## Resolved - a52c1810e

**A fourth arm, not the three this ticket names.** The write path
(`write of a variant — needs the slot ADDRESS, not its value`) was a refusal
standing behind the store, and it appeared the moment the store lowered. That
is the shadowed-gap shape `bug-a-the-wasm32-coverage-report-shows-one-refusal-per-body`
describes, on the same backend the same evening.

**A stack machine makes this the small arm.** The register backends spend most
of their variant code shuffling an address and an 8-byte payload around a
helper call that clobbers them; here the operand stack survives the call and
the two values that must outlive it go in locals -- ~120 lines against
riscv32's ~400. The ORDER is riscv32's exactly, including the two orderings
that are each a fixed bug rather than a preference: payload before destination
(PXXVarClear frees the old value), and PXXVarReleasePayload rather than
PXXVarClear on the copy path (`v := v` must not wipe what it is about to read).

**The scope-exit release is proven reached, from the artefact.** This ticket
says the PXXVarClear arm was written and unverified because nothing could
reach it. `wasm2wat` of a procedure holding a variant local shows `call 86` --
PXXVarClear by its own export name -- twice: the store's clear-before-write and
the epilogue. A 200k survival loop passes too and is NOT what settles it: a
leak does not corrupt, so every value assertion still passes either way.

**The FPC seed canary earned its place.** Three arms are called from earlier in
the file than they are defined. PXX prescans headers and FPC is single-pass, so
it built clean here and failed there with `Identifier not found`. Caught only
because `gate.sh quick` ran while `compiler/**` was still uncommitted; on a
clean tree the canary prints SKIP and this lands.

**Not verified here, and named rather than left implied:** the two RTL-dependent
rows riscv32 runs (`test_variant_comparison_coerces_a_stringy_operand` and the
`-Fulib/rtl` payload row) are NOT wired for wasm32, because `-Fulib/rtl` pulls
the POSIX platform backend whose syscall numbers do not exist for wasi. That
failure has nothing to do with variants and would read as though it did.

## The umbrella edge does not move this in the ranker (frankuser, 2026-09-03)

Wired under `umbrella-wasm-is-a-real-platform` on the census, correctly and in
the right direction -- but `effective_prio` is the max of a ticket's own prio
and everything it unblocks, this ticket is 30 and that umbrella is 25, so
max(30, 25) = 30 and nothing moved. **The measurement cannot promote the work,
because the umbrella expressing the goal is ranked below the ticket serving
it.** Umbrella prio is the only number a human sets, so that is the owner's
call, not an agent's. Recorded here because the next reader of this edge would
otherwise assume it did something.

## Log
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 6a086c2f9.
