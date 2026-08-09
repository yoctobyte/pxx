---
track: A
prio: 55
type: bug
blocked-by: []
status: done
---

# A set- or fixed-array-returning function answers an empty/partial value

- **Type:** bug (function-result ABI; silent wrong value) — **Track A**
- **Found:** 2026-08-09, an FPC differential over a parameter-modes ×
  aggregate-kinds matrix, run right after
  [[bug-a-set-and-shortstring-value-params-alias-the-caller]] because bugs
  cluster and the neighbouring shapes had never been diffed.
- **Pre-existing:** identical on `pinned`.

```pascal
function MkSet: TSet;  begin MkSet := [1, 4]; end;         { FPC: {1,4} }
function MkArr: TArr;  begin MkArr[0] := 8; MkArr[1] := 9; MkArr[2] := 10; end;

s := MkSet;   { pxx: the EMPTY set — 1 in s is False }
a := MkArr;   { pxx: 8 0 0 }
```

Both silent, both on every target. Every way of producing the set failed
(literal, via a local, from a global, built up with `+`); only a `var`
parameter worked, which is what localised it to the RESULT path.

## Two different causes

**The set** — `FuncName := [1, 4]` leaves the LHS `ASTTk` unset (0), and the
set arm of the assignment lowering tested the NODE type only, so the assignment
fell through to the scalar store and wrote the literal's ADDRESS into the
32-byte Result slot. The **record arm immediately below it already carries the
symbol-TypeKind fallback for exactly this case**, comment and all — the set arm
is the sibling that never got it. Textbook
`devdocs/dev/normalise-dont-special-case.md`: fix one arm of a double case,
grep for the sibling.

**The array** — `function F: TArr` records the ELEMENT kind in
`Procs[].RetType`, so `RetViaHiddenDest` (a kind-only predicate) answered False
and **no hidden destination was allocated anywhere**. The callee filled its
Result array correctly and then returned element 0 in a register. The parser now
records the byte size in `ProcRetFixedArrBytes` and the new
`ABIRetViaHiddenDestProc` in the ABI oracle joins the two, so the caller
allocates a right-sized scratch, the callee's epilogue copies into it, and
`a := MkArr` copies the whole array out of it (a new assignment arm — the
existing whole-array arm requires an LVALUE on the right, and a call is not
one).

That the array half needed a per-proc marker is the ABI oracle's case in
miniature: the type's identity was not recoverable from the kind, so five
backends and the return path each answered a question they could not answer.
Every one of them now asks `ABIRetViaHiddenDestProc`.

## Scope, deliberately narrowed twice — both by measurement

- **i386 and arm32 refuse a fixed-array result** with a diagnostic. Wiring the
  whole path through still faults on both; arm32 faulted BEFORE this work too
  (`pinned` SIGSEGVs on the same program), and i386 previously said "arrays not
  yet supported". A clear refusal beats a crash and beats a vague message.
  Follow-up: [[bug-a-fixed-array-function-result-faults-on-i386-and-arm32]].
- **A MULTI-DIMENSIONAL array result is refused.** It is wrong before it is
  ever returned: the callee's own `MkArr2[0,1] := 2` lands in the wrong slot
  (`inside 1 3 3 4` for 1,2,3,4 — on `pinned` too), so returning it correctly
  would only deliver the callee's garbage faithfully. Follow-up:
  [[bug-a-nd-array-function-result-indexes-the-wrong-slot]].

## Verified

`test/test_aggregate_function_results.pas` — every set-result shape, the array
result twice (fresh and over a dirtied destination), and record/shortstring
results as controls. Byte-identical to FPC's own output on x86-64, and the same
last line on aarch64 and riscv32 under qemu.
The 30-row parameter × aggregate matrix that found this now matches FPC exactly.
`make compiler/pascal26` fixedpoint + `tools/gate.sh quick` + `make test-core`
(a new compiler global — the MAX_GLOBFIX landmine only the `--threadsafe`
self-host shows) GREEN.

## Log
- 2026-08-09 — resolved, commit PENDING-COMMIT.
